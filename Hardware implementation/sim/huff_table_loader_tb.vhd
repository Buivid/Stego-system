library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity huff_table_loader_tb is
end huff_table_loader_tb;

architecture Sim of huff_table_loader_tb is
    -- Компонент

    -- Сигналы
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '0';
    signal data_in         : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid      : std_logic := '0';
    signal start           : std_logic := '0';
    signal min_code        : std_logic_vector(15 downto 0);
    signal max_code        : std_logic_vector(15 downto 0);
    signal val_ptr         : integer range 0 to 256;
    signal huff_len        : integer range 0 to 15;
    signal huff_val        : std_logic_vector(7 downto 0);
    signal table_id        : std_logic_vector(1 downto 0);
    signal done            : std_logic;
    signal data_in_ready   : std_logic;
    signal values_valid    : std_logic;
    signal counts_valid    : std_logic;
    -- Период тактового сигнала
    constant CLK_PERIOD : time := 10 ns;

    -- Тестовые данные (JPEG DHT сегмент из вашего примера)
    type byte_array is array (0 to 30) of std_logic_vector(7 downto 0);
constant TEST_DATA : byte_array := (
--        x"FF", x"C4",                   -- Маркер DHT (Define Huffman Table)
        x"00", x"1F",                   -- Длина сегмента (31 байт)
        x"00",                          -- Info: DC Table, ID 0
        -- BITS: Количество кодов каждой длины (от 1 до 16 бит)
        x"00", x"01", x"04", x"03", x"01", x"01", x"01", x"01", 
        x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", 
        -- Symbols: Значения (Huffman values)
        x"07", x"05", x"06", x"08", x"09", x"03", x"04", x"0A", 
        x"02", x"01", x"00", x"0B"
    );

begin

U_load_huff: entity work.huff_table_loader
port map(
        clk => clk,
        rst => rst,
        start => start,
        data_in => data_in,
        data_in_valid => data_valid,
--        data_in_last => byte_last,
        data_in_ready => data_in_ready,
        min_code => min_code,
        max_code => max_code,
        val_ptr => val_ptr,
        huff_len => huff_len,
        counts_valid => counts_valid,
        huff_val => huff_val,
        values_valid => values_valid,
        table_id => table_id,
        table_done => done);

    -- Генерация тактов
    clk_process : process
    begin
        clk <= '1';
        wait for CLK_PERIOD/2;
        clk <= '0';
        wait for CLK_PERIOD/2;
    end process;

    -- Стимулы
    stim_proc: process
    begin		
        -- Сброс
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 1. Эмулируем нахождение маркера FFC4
        -- Подаем FF C4 и держим dht_start
--        data_valid <= '1';
--        data_in <= TEST_DATA(0); -- FF
--        wait for CLK_PERIOD;
        
--        data_in <= TEST_DATA(1); -- C4
        start <= '1'; 
        wait for clk_period;
        data_in <= TEST_DATA(2);
        start <= '0';        
       -- Сигнализируем парсеру о начале
        wait for CLK_PERIOD;


        -- 2. Передаем оставшуюся часть потока (Длина + Таблица)
        for i in 0 to TEST_DATA'high loop

--            data_in <= TEST_DATA(i);
--            data_valid <= '1';
--            wait for CLK_PERIOD;
--            data_valid <= '0';
            loop
--               data_valid <= '0';
                wait until rising_edge(clk);
                -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
                exit when data_in_ready = '1'; 
            end loop;
            data_in <= TEST_DATA(i);
            data_valid <= '1';
            wait for CLK_PERIOD;
--            data_valid <= '0';
--            wait for clk_period;
            -- Можно добавить случайные паузы (data_valid = '0'), 
            -- чтобы проверить устойчивость парсера к прерывистому потоку
        end loop;
--        wait for clk_period;
--        data_valid <= '0';
--        data_in <= x"00";

        -- Ждем завершения обработки
        wait until done = '1';
--        wait for CLK_PERIOD * 10;

        -- Завершение симуляции
        assert false report "Simulation Finished" severity note;
        wait;
    end process;

end Sim;