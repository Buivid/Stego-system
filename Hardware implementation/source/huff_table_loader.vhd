
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity huff_table_loader is
   Port (
     clk             : in  STD_LOGIC;
     rst             : in  STD_LOGIC;
     start           : in  STD_LOGIC; -- Сигнал от верхнего уровня "Нашли FFC4"
             
     -- Вход от входного потока
     data_in         : in  STD_LOGIC_VECTOR(7 downto 0);
     data_in_valid   : in  STD_LOGIC;
     data_in_ready   : out STD_LOGIC;
--     data_out_valid  : out std_logic;
     
     -- Выход на память таблиц
--        table_write_en  : out STD_LOGIC;
--        table_addr      : out STD_LOGIC_VECTOR(15 downto 0); 
     min_code        : out std_logic_vector(15 downto 0);
     max_code        : out std_logic_vector(15 downto 0);
     val_ptr         : out integer range 0 to 255;
     huff_len        : out integer range 0 to 15;
     counts_valid    : out std_logic;
     huff_val        : out std_logic_vector(7 downto 0);
     values_valid    : out std_logic;
     table_id        : out std_logic_vector(1 downto 0);
--        table_data      : out STD_LOGIC_VECTOR(7 downto 0);
     

     table_done      : out std_logic
 );
end huff_table_loader;

architecture Behavioral of huff_table_loader is
  type state_type is (IDLE, READ_LEN, READ_INFO, READ_COUNTS, READ_SYMBOL, DONE);
  signal state : state_type := IDLE;
  
  signal length: integer range 0 to 65535:=0;
  signal cnt_len: integer range 0 to 65535:=0; 
  signal byte_cnt: integer range 0 to 512 := 0;
--    signal table_id: std_logic_vector(7 downto 0):=(others=>'0');
  signal symbol_cnt  : integer range 0 to 256 := 0;
  signal total_symbols : integer range 0 to 256 := 0;
  
  -- Хранилище количества кодов разной длины (16 байт)
type counts_array is array (0 to 15) of integer range 0 to 255;
signal counts : counts_array;  

type min_code_array is array(0 to 15) of std_logic_vector(15 downto 0);
signal min_codes: min_code_array; 
     
signal code: std_logic_vector(15 downto 0):=(others=>'0');
signal curr_val: std_logic_vector(7 downto 0);
signal curr_len: integer range 0 to 15 := 0;
signal curr_code: std_logic_vector(15 downto 0):=(others => '0');
signal symbol_idx: integer range 0 to 255:= 0;
signal data_in_ready_reg: std_logic;
begin
  process(clk)
  begin
      if rising_edge(clk) then
          if rst = '1' then
              state <= IDLE;
          else
          case state is
          when IDLE =>
              if start = '1' then
                  state <= READ_LEN;
              end if;
          when READ_LEN =>
              if byte_cnt = 1 then
                  state <= READ_INFO;
              end if;
          when READ_INFO =>
              state <= READ_COUNTS;
          when READ_COUNTS =>
              if byte_cnt = 15 then
                  state <= READ_SYMBOL;
              end if;
--            when FIND_LEN =>
--                if counts(byte_cnt) /= 0 then
--                    state <= READ_SYMBOL;
--                elsif
--                    cnt_len = length then
--                        state <= DONE;
--                end if;     
          when READ_SYMBOL =>
              if cnt_len = length - 1 then
                  state <= DONE;
--                elsif counts(byte_cnt) = 1 then--and byte_cnt < 15 then
--                    state <= FIND_LEN;
              end if;
          when DONE =>
              state <= IDLE;
          end case;
          end if;
      end if;
  end process;
  
  process(clk)
--  variable curr_code: std_logic_vector(15 downto 0):= (others => '0');
  begin
      if rising_edge(clk)then
          if rst = '1' then
              byte_cnt <= 0;
              counts_valid <= '0';
              values_valid <= '0';
              curr_code <= (others => '0');
              curr_len <= 0;
              symbol_idx <= 0;
              data_in_ready <= '0';
          else
              case state is
              when IDLE =>
                  byte_cnt <= 0;
                  length <= 0;
                  cnt_len <= 0;
                  total_symbols <= 0;
                  data_in_ready <= '1';
                  counts_valid <= '0';
                  values_valid <= '0';
                  curr_code <= (others => '0');
                  curr_len <= 0;
                  code <= (others => '0');
                  table_done <= '0';
                  curr_len <= 0;
              when READ_LEN =>
                  if data_in_valid = '1' then
                      if byte_cnt < 1 then
                          length <= to_integer(shift_left(to_unsigned(length, 16), 8)) + to_integer(unsigned(data_in));
                      else--if byte_cnt = 1 then
                          length <= length + to_integer(unsigned(data_in));
                      end if;
                      byte_cnt <= byte_cnt + 1;
                      cnt_len <= cnt_len + 1;
                  end if;
              when READ_INFO =>
                  if data_in_valid = '1' then
                      byte_cnt <= 0;
                      table_id <= data_in(4) & data_in(0);
                      cnt_len <= cnt_len + 1;
                      
                  end if;
              when READ_COUNTS =>
                  if data_in_valid = '1' then 
                      counts_valid <= '1';
                      huff_len <= byte_cnt;
                      counts(byte_cnt) <= to_integer(unsigned(data_in));                     
                      if data_in /= x"00" then
                          min_code <= code;
                          min_codes(byte_cnt) <= code;
                          max_code <= std_logic_vector(unsigned(code) + unsigned(data_in) - 1);
                          val_ptr <= total_symbols;
                          total_symbols <= total_symbols + to_integer(unsigned(data_in));
                          code <= std_logic_vector(shift_left(unsigned(code) + unsigned(data_in), 1));                          
                      else
                          min_codes(byte_cnt) <= (others => '0');
                          min_code <= x"0001";
                          max_code <= x"0000";
                          code <= std_logic_vector(shift_left(unsigned(code), 1));
                      end if;
                      if byte_cnt = 15 then
                          byte_cnt <= 0;
                          counts_valid <= '0';
                          data_in_ready <= '0';
                      else
                          byte_cnt <= byte_cnt + 1;
                          cnt_len <= cnt_len + 1;
                      end if;  
--                        counts(byte_cnt) <= unsigned(data_in);
--                        total_symbols <= total_symbols + to_integer(unsigned(data_in));

--                        if byte_cnt = 14 then
--                            data_out_valid <= '0';
--                        end if;
                  end if;
              when READ_SYMBOL =>
                  if data_in_valid = '1' and data_in_ready_reg = '1' then
                    values_valid <= '1';
                    huff_val <= data_in;
                    huff_len <= curr_len;
                    min_code <= curr_code;
                    curr_code <= std_logic_vector(unsigned(curr_code) + 1);
                  else
                    values_valid <= '0';
                  end if;     
                      
                  if counts(curr_len) > 0 then
                    cnt_len <= cnt_len + 1;
                    data_in_ready_reg <= '1';
                    data_in_ready <= '1';
                    
                    counts(curr_len) <= counts(curr_len) - 1;
--                        values_valid <= '1';
                  else
                    data_in_ready_reg <= '0';
                    data_in_ready <= '0';
--                        values_valid <= '0';
--                        if counts(curr_len) = 1 then
--                            data_in_ready <= '1';
--                            values_valid <= '1';
--                        else
--                            data_in_ready <= '0';
--                            values_valid <= '0';
--                        end if;
                  end if;
                  if counts(curr_len) = 0 then
                  for i in curr_len + 1 to 15 loop
                      if counts(i) /= 0 then
                          curr_len <= i;
                          curr_code <= min_codes(i);
                          exit;
                      end if;
                  end loop;
                  end if;
                      
                      if cnt_len = length - 1 then
                          data_in_ready <= '0';
                      end if;
--                        table_addr <= code;
--                        if counts(byte_cnt) = 1 then
--                            pending_increment <= '1';
--                            ready_for_data <= '0';
--                        else
--                            code <= std_logic_vector(unsigned(code) + 1);
--                        end if;
--                        counts(byte_cnt) <= counts(byte_cnt) - 1;

--                        not_first <= '1';

              when DONE =>
                  table_done <= '1';
                  data_in_ready <= '0';
                  values_valid <= '0';
              end case;
          end if;
      end if;
  end process;
end Behavioral;
