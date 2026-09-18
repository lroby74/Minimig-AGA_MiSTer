-- Measure what the TG68K kernel actually costs per instruction.
--
-- The cycle model can hold the CPU to stretch an instruction out to what a
-- 68030 would take. It cannot shorten one. So an instruction costs
-- max(what the core needs, what the tables say), and at the higher clock
-- targets the core is the one setting the pace. This counts the core's side
-- of that: clock enables per instruction, with memory answering instantly, so
-- what comes out is the pipeline alone with no bus wait in it.
--
--   ghdl -a --std=93c -fsynopsys -fexplicit -frelaxed <kernel files> tb_cpi.vhd
--   ghdl -e ... tb_cpi && ./tb_cpi --generic-value
--
-- The program under test is a raw 68k binary named by the PROG generic, loaded
-- at address 0. The first two longwords are the reset stack pointer and PC,
-- as the processor expects.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_cpi is
	generic(
		PROG   : string  := "prog.hex";
		WARMUP : integer := 200;       -- instructions to skip before counting
		COUNT  : integer := 2000;      -- instructions to average over
		TRACE  : string  := ""         -- if set, write every opcode started here
	);
end tb_cpi;

architecture sim of tb_cpi is
	signal clk       : std_logic := '0';
	signal nreset    : std_logic := '0';
	signal data_in   : std_logic_vector(15 downto 0) := (others => '0');
	signal addr_out  : std_logic_vector(31 downto 0);
	signal data_wr   : std_logic_vector(15 downto 0);
	signal nwr, nuds, nlds, nresetout, skipf : std_logic;
	signal busstate  : std_logic_vector(1 downto 0);
	signal fc        : std_logic_vector(2 downto 0);
	signal longword, clr_berr : std_logic;
	signal regin, vbr : std_logic_vector(31 downto 0);
	signal cacr      : std_logic_vector(3 downto 0);
	signal dcache    : std_logic;
	signal opc_start : std_logic;
	signal opc_out   : std_logic_vector(15 downto 0);
	signal opc_cond  : std_logic;
	signal opc_snd   : std_logic_vector(15 downto 0);
	signal opc_dbx   : std_logic;

	type ram_t is array (0 to 65535) of std_logic_vector(15 downto 0);
	shared variable ram : ram_t := (others => x"4E71");
	signal addr_w : integer := 0;
begin

	clk <= not clk after 5 ns;

	cpu: entity work.TG68KdotC_Kernel
		generic map (SR_Read => 2, VBR_Stackframe => 2, extAddr_Mode => 2,
		             MUL_Mode => 2, DIV_Mode => 2, BitField => 2,
		             BarrelShifter => 1, MUL_Hardware => 1)
		port map (
			clk => clk, nReset => nreset, clkena_in => '1',
			data_in => data_in, IPL => "111", IPL_autovector => '1', berr => '0',
			CPU => "11", CPU030 => '1',
			addr_out => addr_out, data_write => data_wr,
			nWr => nwr, nUDS => nuds, nLDS => nlds, busstate => busstate,
			longword => longword, nResetOut => nresetout, FC => fc,
			clr_berr => clr_berr, skipFetch => skipf, regin_out => regin,
			CACR_out => cacr, D_CACHE_out => dcache, VBR_out => vbr,
			opc_start => opc_start, opc_out => opc_out, opc_cond => opc_cond,
			opc_snd => opc_snd, opc_dbx => opc_dbx);

	addr_w <= to_integer(unsigned(addr_out(16 downto 1)));

	-- memory answers in the same cycle, so nothing here adds wait states
	data_in <= ram(addr_w);

	mem: process(clk)
	begin
		if rising_edge(clk) then
			if busstate = "11" and nwr = '0' then
				ram(addr_w) := data_wr;
			end if;
		end if;
	end process;

	load: process
		file f      : text;
		variable l  : line;
		variable v  : integer;
		variable i  : integer := 0;
	begin
		file_open(f, PROG, read_mode);
		while not endfile(f) loop
			readline(f, l);
			read(l, v);
			ram(i) := std_logic_vector(to_unsigned(v, 16));
			i := i + 1;
		end loop;
		file_close(f);
		wait for 40 ns;
		nreset <= '1';
		wait;
	end process;

	meter: process(clk)
		file tf         : text;
		variable topen  : boolean := false;
		variable tl     : line;
		variable n      : integer := 0;
		variable cyc    : integer := 0;
		variable t0     : integer := 0;
		variable started: boolean := false;
		variable first  : std_logic_vector(15 downto 0);
		variable l      : line;
		-- a line is held back one cycle: sndOPC takes the word after the
		-- opcode in the same clkena opc_start is in, so it has settled by the
		-- next one, which is where rtl/cpu_cycles.v reads it too
		variable pend   : boolean := false;
		variable p_op   : std_logic_vector(15 downto 0);
		variable p_cond : std_logic;
		-- whether the instruction before this one was the iteration a DBcc
		-- loop ran out on, which is what cpu_cycles carries forward too
		variable p_dbx  : std_logic := '0';
		variable dbx_v  : std_logic := '0';
	begin
		if rising_edge(clk) and nreset = '1' then
			if TRACE /= "" and not topen then
				file_open(tf, TRACE, write_mode); topen := true;
			end if;
			cyc := cyc + 1;
			if pend then
				-- the opcode, the condition of the one before it, and the word after it
				write(tl, to_integer(unsigned(p_op)));
				write(tl, string'(" "));
				if p_cond = '1' then write(tl, 1); else write(tl, 0); end if;
				write(tl, string'(" "));
				write(tl, to_integer(unsigned(opc_snd)));
				write(tl, string'(" "));
				if p_dbx = '1' then write(tl, 1); else write(tl, 0); end if;
				writeline(tf, tl);
				pend := false;
			end if;
			if opc_dbx = '1' then dbx_v := '1'; end if;
			if opc_start = '1' then
				n := n + 1;
				if topen and n > WARMUP and n < WARMUP + COUNT then
					p_op := opc_out; p_cond := opc_cond; p_dbx := dbx_v; pend := true;
				end if;
				dbx_v := '0';
				if n = WARMUP then
					t0 := cyc; started := true; first := opc_out;
				elsif started and n = WARMUP + COUNT then
					write(l, string'("opcode "));
					write(l, to_integer(unsigned(first)));
					write(l, string'("  cycles/instruction "));
					write(l, real(cyc - t0) / real(COUNT), right, 8, 3);
					writeline(output, l);
					if topen then file_close(tf); end if;
					assert false report "done" severity failure;
				end if;
			end if;
			if cyc > 20000000 then
				write(l, string'("TIMEOUT"));
				writeline(output, l);
				assert false report "timeout" severity failure;
			end if;
		end if;
	end process;

end sim;
