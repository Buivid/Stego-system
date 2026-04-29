library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_decode_module is
-- Тестбенч не имеет портов
end tb_decode_module;

architecture Behavioral of tb_decode_module is

    -- Компонент
    component decode_module
        Port (
            clk             : in  STD_LOGIC;
            rst             : in  STD_LOGIC;
            data_in         : in  STD_LOGIC_VECTOR(31 downto 0);
            data_in_valid   : in  STD_LOGIC;
            ready_in        : out STD_LOGIC;
            data_out        : out STD_LOGIC_VECTOR(31 downto 0);
            data_out_valid  : out STD_LOGIC;
            ready_out       : in  STD_LOGIC
        );
    end component;

    -- Сигналы для подключения
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '0';
    signal s_data_in      : std_logic_vector(31 downto 0) := (others => '0');
    signal s_data_in_valid: std_logic := '0';
    signal s_ready_in     : std_logic;
    signal s_data_out     : std_logic_vector(31 downto 0);
    signal s_data_out_valid: std_logic;
    signal s_ready_out    : std_logic := '0';

    -- Константы периода тактового сигнала
    constant CLK_PERIOD : time := 10 ns;

    -- Тестовые данные (JPEG DHT сегмент из вашего примера)
    type byte_array1 is array (0 to 48) of std_logic_vector(31 downto 0);
constant TEST_DATA : byte_array1 := (
        x"12345678", x"87654321",
        x"FFC4001F", x"00000104", x"03010101", x"01000000",
        x"00000000", x"00070506", x"08090304", x"0A020100",
        x"0BFFDA00", x"3B100003", x"01000104", x"02020202",
        x"01040102", x"000F0102", x"03040506", x"11121307",
        x"14082221", x"23000915", x"24313233", x"16174142",
        x"0A253443", x"27182628", x"35445152", x"5372FFC4",
        x"001E0100", x"01040301", x"01010000", x"00000000",
        x"00000503", x"04060701", x"02080900", x"0AFFC400",
        x"3B110003", x"00020201", x"03030401", x"04010401",
        x"000B0102", x"03041211", x"13050621", x"22071423",
        x"00083132", x"15243341", x"42511617", x"43523409",
        x"25611826", x"53627135", x"72810000"  -- padding до 4 байт
    );
type byte_array2 is array (0 to 64) of std_logic_vector(31 downto 0);   
constant JPEG_DUMP : byte_array2 := (
    x"FFD8FFE0", x"00104A46", x"49460001", x"010100C8",
    x"00C80000", x"FFFFC400", x"1F000001", x"04030101",
    x"01010000", x"00000000", x"00000705", x"06080903",
    x"040A0201", x"000BFFC4", x"003B1000", x"03010001",
    x"04020202", x"02010401", x"02000F01", x"02030405",
    x"06111213", x"07140822", x"21230009", x"15243132",
    x"33161741", x"420A2534", x"43271826", x"28354451",
    x"525372FF", x"C4001E01", x"00010403", x"01010100",
    x"00000000", x"00000000", x"05030406", x"07010208",
    x"09000AFF", x"C4003B11", x"00030002", x"02010303",
    x"04010401", x"0401000B", x"01020304", x"12111305",
    x"06212207", x"14230008", x"31321524", x"33414251",
    x"16174352", x"34092561", x"18265362", x"71357281",
    x"FFDA000C", x"03010002", x"11031100", x"3F00809F",
    x"15F42FC7", x"9C87C3DF", x"16BDFA33", x"A42FAB4F",
    x"C61D0FB3", x"7E8D3D29", x"C2396D2F", x"D3FC7FD8",
    x"DD5D17CB"
);

begin

    -- Тактовый генератор
    clk_process : process
    begin
        clk <= '1';
        wait for CLK_PERIOD/2;
        clk <= '0';
        wait for CLK_PERIOD/2;
    end process;

    -- Экземпляр тестируемого модуля (UUT)
    uut: decode_module port map (
        clk => clk,
        rst => rst,
        data_in => s_data_in,
        data_in_valid => s_data_in_valid,
        ready_in => s_ready_in,
        data_out => s_data_out,
        data_out_valid => s_data_out_valid,
        ready_out => s_ready_out
    );

    -- Стимулы (логика подачи данных)
    stim_proc: process
    file data_file : text;
    variable file_line : line;
    variable hex_val: std_logic_vector(31 downto 0);
    variable file_status: file_open_status;
    begin		
    
        -- Сброс
        rst <= '1';
        wait for 20 ns;
        rst <= '0';
        wait for 2*CLK_PERIOD;
        
        file_open(file_status, data_file, "input_data.txt", read_mode);
        if file_status /= open_ok then
            report "err" severity failure;
        end if;
        
        s_ready_out <= '1';
        while not endfile(data_file) loop
            readline(data_file, file_line);
            hread(file_line, hex_val);
            s_data_in <= hex_val;
            s_data_in_valid <= '1';
--            if s_data_out_valid = '1' then
--                s_ready_out <= '1';
--            else 
--                s_ready_out <= '0';
--            end if;
            wait until rising_edge(clk) and s_ready_in = '1';
        end loop;
        s_data_in_valid <= '0';
        file_close(data_file);        
        -- СЦЕНАРИЙ 1: Идеальная передача (Back-to-back)
        -- Приемник готов, подаем 3 слова подряд
--        s_ready_out <= '1'; 
        
--        for i in 0 to JPEG_DUMP'high loop
--        s_data_in <= JPEG_DUMP(i);
--        s_data_in_valid <= '1';
--        wait for CLK_PERIOD;
--        loop
--        wait until rising_edge(clk);
--            -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
--        exit when s_ready_in = '1'; 
--        end loop;

--            s_data_in <= TEST_DATA(i);
--            s_data_in_valid <= '1';
            
--            -- Ждем, пока произойдет рукопожатие (такт)
--            wait until rising_edge(clk) and s_ready_in = '1';
--        end loop;
        
--        s_data_in_valid <= '0';
--        wait for CLK_PERIOD * 2;

--        -- СЦЕНАРИЙ 2: Приемник не готов (Backpressure)
--        -- Подаем данные, но имитируем, что выходной интерфейс занят
--        s_ready_out <= '0'; 
--        s_data_in <= x"FFFF0156";
--        s_data_in_valid <= '1';
        
--        wait for CLK_PERIOD * 3; 
--        -- Теперь "освобождаем" приемник
--        s_ready_out <= '1';
        
--        wait until rising_edge(clk) and s_ready_in = '1';


        -- Завершение симуляции
        wait for 100 ns;
        assert false report "Simulation Finished" severity failure;
    end process;

end Behavioral;