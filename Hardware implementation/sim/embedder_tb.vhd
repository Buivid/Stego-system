library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_embedder is
end entity;

architecture sim of tb_embedder is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal start : std_logic := '0';
  signal emb_bit : std_logic := '0';

  signal data_in : std_logic_vector(31 downto 0);
  signal data_in_valid : std_logic := '0';
  signal data_in_last  : std_logic := '0';
  signal data_in_ready : std_logic;

  signal data_out : std_logic_vector(31 downto 0);
  signal data_out_valid : std_logic;
  signal data_out_last  : std_logic;
  signal data_out_ready : std_logic := '1';

  signal done : std_logic;

begin

  --------------------------------------------------
  -- DUT
  --------------------------------------------------
  uut : entity work.embedder
    port map (
      clk => clk,
      rst => rst,
      start => start,
      emb_bit => emb_bit,
      data_in => data_in,
      data_in_valid => data_in_valid,
      data_in_last => data_in_last,
      data_in_ready => data_in_ready,
      data_out => data_out,
      data_out_valid => data_out_valid,
      data_out_last => data_out_last,
      data_out_ready => data_out_ready,
      done => done
    );

  --------------------------------------------------
  -- Clock
  --------------------------------------------------
  clk <= not clk after 5 ns;

  --------------------------------------------------
  -- Stimulus
  --------------------------------------------------
  process
    variable cnt : integer := 0;
  begin

    -- reset
    wait for 20 ns;
    rst <= '0';

    -- старт
    wait for 10 ns;
    start <= '1';
    wait for 10 ns;
    start <= '0';

    --------------------------------------------------
    -- подача данных
    --------------------------------------------------
    for i in 0 to 32 loop

      wait until rising_edge(clk);

      if data_in_ready = '1' then
        data_in_valid <= '1';

        -- генерим 2 коэффициента
        data_in(31 downto 16) <= std_logic_vector(to_signed(i,16));
        data_in(15 downto 0)  <= std_logic_vector(to_signed(i+100,16));

        if i = 31 then
          data_in_last <= '1';
        else
          data_in_last <= '0';
        end if;

      else
        data_in_valid <= '0';
      end if;

    end loop;

    data_in_valid <= '0';
    data_in_last  <= '0';

    --------------------------------------------------
    -- ждём завершение
    --------------------------------------------------
    wait until done = '1';

    wait for 50 ns;

    assert false report "SIMULATION FINISHED" severity failure;

  end process;

  --------------------------------------------------
  -- Монитор (очень полезно)
  --------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if data_out_valid = '1' then
        report "OUT: " &
          integer'image(to_integer(signed(data_out(31 downto 16)))) & " , " &
          integer'image(to_integer(signed(data_out(15 downto 0))));
      end if;
    end if;
  end process;

end architecture;