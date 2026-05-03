library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;

entity bitstream_decoder_tb is
-- Тестбенч не имеет портов
end bitstream_decoder_tb;

architecture Behavioral of bitstream_decoder_tb is

    -- Сигналы для подключения
signal clk            : std_logic := '0';
signal rst            : std_logic := '0';
signal start_hload: std_logic:= '0';
signal byte_data: std_logic_vector(7 downto 0);
signal byte_valid: std_logic:= '0';
signal byte_ready: std_logic:= '0';
signal min_code: std_logic_vector(15 downto 0);
signal max_code: std_logic_vector(15 downto 0);
signal val_ptr: integer range 0 to 255;
signal huff_len: integer range 0 to 15;
signal huff_val: std_logic_vector(7 downto 0);
signal table_id: std_logic_vector(1 downto 0);
signal counts_valid: std_logic;
signal values_valid: std_logic;
signal done_hload: std_logic;

signal start_decode: std_logic:='0';
signal data_in: std_logic_vector(31 downto 0);
signal data_in_valid: std_logic;
signal data_in_last: std_logic;
signal decode_data_out: std_logic_vector(31 downto 0);
signal decode_data_out_valid: std_logic;
signal decode_data_out_last: std_logic;
signal decode_data_in_ready: std_logic;
signal data_out_ready: std_logic;
signal done_decode: std_logic;

    -- Константы периода тактового сигнала
constant CLK_PERIOD : time := 10 ns;

    -- Тестовые данные (JPEG DHT сегмент из вашего примера)
type t1_type is array (0 to 30) of std_logic_vector(7 downto 0);
constant HUFF_TABLE1 :  t1_type:= (
x"00", x"1f", x"00", x"00", x"01", x"04", x"03", x"01", x"01", x"01", x"01", x"00", x"00", x"00", x"00", x"00",
x"00", x"00", x"00", x"07", x"05", x"06", x"08", x"09", x"03", x"04", x"0a", x"02", x"01", x"00", x"0b");

type t2_type is array (0 to 58) of std_logic_vector(7 downto 0);   
constant HUFF_TABLE2 : t2_type := (
x"00", x"3b", x"10", x"00", x"03", x"01", x"00", x"01", x"04", x"02", x"02", x"02", x"02", x"01", x"04", x"01",
x"02", x"00", x"0f", x"01", x"02", x"03", x"04", x"05", x"06", x"11", x"12", x"13", x"07", x"14", x"08", x"22",
x"21", x"23", x"00", x"09", x"15", x"24", x"31", x"32", x"33", x"16", x"17", x"41", x"42", x"0a", x"25", x"34",
x"43", x"27", x"18", x"26", x"28", x"35", x"44", x"51", x"52", x"53", x"72");

type t3_type is array (0 to 29) of std_logic_vector(7 downto 0);
constant HUFF_TABLE3: t3_type := (
x"00", x"1e", x"01", x"00", x"01", x"04", x"03", x"01", x"01", x"01", x"00", x"00", x"00", x"00", x"00", x"00",
x"00", x"00", x"00", x"05", x"03", x"04", x"06", x"07", x"01", x"02", x"08", x"09", x"00", x"0a");

type t4_type is array(0 to 58) of std_logic_vector(7 downto 0);
constant HUFF_TABLE4: t4_type := (
x"00", x"3b", x"11", x"00", x"03", x"00", x"02", x"02", x"01", x"03", x"03", x"04", x"01", x"04", x"01", x"04",
x"01", x"00", x"0b", x"01", x"02", x"03", x"04", x"12", x"11", x"13", x"05", x"06", x"21", x"22", x"07", x"14",
x"23", x"00", x"08", x"31", x"32", x"15", x"24", x"33", x"41", x"42", x"51", x"16", x"17", x"43", x"52", x"34",
x"09", x"25", x"61", x"18", x"26", x"53", x"62", x"71", x"35", x"72", x"81");

type SOS_type is array(0 to 9) of std_logic_vector(31 downto 0);
constant BITSTREAM: SOS_type:= (
x"809f15f4", x"2fc79c87", x"c3df16bd", x"fa33a42f",
x"ab4fc61d", x"0fb37e8d", x"3d29c239", x"6d2fd3fc",
x"7fd8dd5d", x"17cb4bd3");


begin

U_load_huff: entity work.huff_table_loader
port map(
        clk => clk,
        rst => rst,
        start => start_hload,
        data_in => byte_data,
        data_in_valid => byte_valid,
--        data_in_last => byte_last,
        data_in_ready => byte_ready,
        min_code => min_code,
        max_code => max_code,
        val_ptr => val_ptr,
        huff_len => huff_len,
        counts_valid => counts_valid,
        huff_val => huff_val,
        values_valid => values_valid,
        table_id => table_id,
        table_done => done_hload);
         
        
U_decode: entity work.bitstream_decoder
port map(
       clk => clk,
       rst => rst,
       start => start_decode,
       data_in => data_in,
       data_in_valid => data_in_valid,
       data_in_last => data_in_last,
       data_in_ready => decode_data_in_ready,
       data_out => decode_data_out,
       data_out_valid => decode_data_out_valid,
       data_out_last => decode_data_out_last,
       data_out_ready => data_out_ready,
       min_code => min_code,
       max_code => max_code,
       val_ptr => val_ptr,
       huff_len => huff_len,
       counts_valid => counts_valid,
       huff_val => huff_val,
       values_valid => values_valid,
       table_id => table_id,       
       done => done_decode
       );
    -- Тактовый генератор
    clk_process : process
    begin
        clk <= '1';
        wait for CLK_PERIOD/2;
        clk <= '0';
        wait for CLK_PERIOD/2;
    end process;

    -- Стимулы (логика подачи данных)
    stim_proc: process

    begin		
    
        -- Сброс
        rst <= '1';
        wait for 20 ns;
        rst <= '0';
        byte_valid <= '0';
        wait for 2*CLK_PERIOD;
        
    --TABLE1

start_hload <= '1';
wait for clk_period;
start_hload <= '0'; 
wait for clk_period;       
for i in 0 to HUFF_TABLE1'high loop
   loop
       wait until rising_edge(clk);
       -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
       exit when byte_ready = '1'; 
   end loop;
   byte_data <= HUFF_TABLE1(i);
   byte_valid <= '1';
   wait for CLK_PERIOD;
end loop;
byte_valid <= '0';
wait for 3*clk_period;

    --TABLE2
start_hload <= '1';
wait for clk_period;
start_hload <= '0'; 
wait for clk_period;       
for i in 0 to HUFF_TABLE2'high loop
   loop
       wait until rising_edge(clk);
       -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
       exit when byte_ready = '1'; 
   end loop;
   byte_data <= HUFF_TABLE2(i);
   byte_valid <= '1';
   wait for CLK_PERIOD;
end loop;
byte_valid <= '0';
wait for 3*clk_period;

        --TABLE3
start_hload <= '1';
wait for clk_period;
start_hload <= '0'; 
wait for clk_period;       
for i in 0 to HUFF_TABLE3'high loop
   loop
       wait until rising_edge(clk);
       -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
       exit when byte_ready = '1'; 
   end loop;
   byte_data <= HUFF_TABLE3(i);
   byte_valid <= '1';
   wait for CLK_PERIOD;
end loop;
byte_valid <= '0';
wait for 3*clk_period;

        --TABLE4
start_hload <= '1';
wait for clk_period;
start_hload <= '0'; 
wait for clk_period;       
for i in 0 to HUFF_TABLE4'high loop
   loop
       wait until rising_edge(clk);
       -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
       exit when byte_ready = '1'; 
   end loop;
   byte_data <= HUFF_TABLE4(i);
   byte_valid <= '1';
   wait for CLK_PERIOD;
end loop;
byte_valid <= '0';
wait for 2*clk_period;

start_decode <= '1';
wait for clk_period;
start_decode <= '0'; 
wait for clk_period;       
for i in 0 to BITSTREAM'high loop
   loop
       wait until rising_edge(clk);
       -- Если приемник подтвердил готовность, выходим из внутреннего ожидания
       exit when decode_data_in_ready = '1'; 
   end loop;
   data_in <= BITSTREAM(i);
   data_in_valid <= '1';
   wait for CLK_PERIOD;
end loop;
data_in_valid <= '0';
wait for clk_period;
        -- Завершение симуляции
        wait for 100 ns;
        assert false report "Simulation Finished" severity failure;
    end process;

end Behavioral;