library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Axis_To_Bitstream_tb is
-- Тестбенч не имеет портов
end Axis_To_Bitstream_tb;

architecture sim of Axis_To_Bitstream_tb is

    -- Параметры синхронизации
    constant CLK_PERIOD : time := 10 ns;

    -- Сигналы для подключения к компоненту
    signal clk           : std_logic := '0';
    signal rst           : std_logic := '0';
    signal s_axis_tdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tvalid  : std_logic := '0';
    signal s_axis_tready  : std_logic;
    signal bit_out       : std_logic;
    signal bit_valid     : std_logic;
    signal bit_ready     : std_logic := '0';

begin

    -- Юнит под тестированием (UUT)
    uut: entity work.Axis_To_Bitstream
        port map (
            clk           => clk,
            rst           => rst,
            s_axis_tdata  => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            bit_out       => bit_out,
            bit_valid     => bit_valid,
            bit_ready     => bit_ready
        );

    -- Генерация тактового сигнала
    clk_process : process
    begin
        while now < 1000 ns loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- Основной процесс тестирования
    stim_proc: process
    begin
        -- Сброс
        rst <= '1';
        wait for 25 ns;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Сценарий 1: Передача первого 32-битного слова
        wait until rising_edge(clk);
        s_axis_tdata  <= x"A5A5A5A5"; -- 10100101...
        s_axis_tvalid <= '1';
        
        wait until s_axis_tready = '1' and rising_edge(clk);
        s_axis_tvalid <= '0'; -- Данные приняты

        -- Сценарий 2: Читаем биты (симулируем готовность декодера)
        wait for CLK_PERIOD * 2;
        bit_ready <= '1'; -- Начинаем забирать биты
        
        -- Ждем, пока вычитается половина слова
        wait for CLK_PERIOD * 16;
        
        -- Сценарий 3: Передача второго слова во время работы
        s_axis_tdata  <= x"FFFF0000";
        s_axis_tvalid <= '1';
        
        wait until s_axis_tready = '1' and rising_edge(clk);
        s_axis_tvalid <= '0';

        -- Сценарий 4: Декодер делает паузу (bit_ready = 0)
        wait for CLK_PERIOD * 5;
        bit_ready <= '0';
        wait for CLK_PERIOD * 5;
        bit_ready <= '1';

        -- Завершение симуляции
        wait for 500 ns;
        assert false report "Simulation Finished" severity note;
        wait;
    end process;

end sim;