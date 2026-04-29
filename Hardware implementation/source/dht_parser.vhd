library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dht_parser is
    Port (
        clk             : in  STD_LOGIC;
        rst             : in  STD_LOGIC;
        dht_start       : in  STD_LOGIC; -- Сигнал от верхнего уровня "Нашли FFC4"
                
        -- Вход от входного потока
        data_in         : in  STD_LOGIC_VECTOR(7 downto 0);
        data_valid      : in  STD_LOGIC;
        ready_for_data  : out STD_LOGIC;
        data_out_valid  : out std_logic;
        
        -- Выход на память таблиц
--        table_write_en  : out STD_LOGIC;
--        table_addr      : out STD_LOGIC_VECTOR(15 downto 0); 
        min_code        : out std_logic_vector(15 downto 0);
        max_code        : out std_logic_vector(15 downto 0);
        val_ptr         : out integer range 0 to 255;
        huff_len        : out integer range 0 to 15;
        huff_val        : out std_logic_vector(7 downto 0);
        table_id        : out std_logic_vector(1 downto 0);
--        table_data      : out STD_LOGIC_VECTOR(7 downto 0);
        

        table_done      : out std_logic
    );
end dht_parser;

architecture Behavioral of dht_parser is
    type state_type is (IDLE, READ_LEN, READ_INFO, READ_COUNTS, READ_SYMBOL, DONE);
    signal state : state_type := IDLE;
    
    signal length: integer range 0 to 65535:=0;
    signal cnt_len: integer range 0 to 65535:=0; 
    signal byte_cnt: integer range 0 to 512 := 0;
--    signal table_id: std_logic_vector(7 downto 0):=(others=>'0');
    signal symbol_cnt  : integer range 0 to 256 := 0;
    signal total_symbols : integer range 0 to 256 := 0;
    
    -- Хранилище количества кодов разной длины (16 байт)
--    type counts_array is array (0 to 15) of unsigned(7 downto 0);
--    signal counts : counts_array;    
    signal code: std_logic_vector(15 downto 0):=(others=>'0');
--    signal not_first: std_logic:='0';
--    signal pending_increment : std_logic := '0';

--    signal counts_idx: integer range 0 to 256:=0; 

begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
            else
            case state is
            when IDLE =>
                if dht_start = '1' then
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
    begin
        if rising_edge(clk)then
            if rst = '1' then
                byte_cnt <= 0;
                data_out_valid <= '0';
                --refreshing registers
            else
                case state is
                when IDLE =>
                    byte_cnt <= 0;
                    length <= 0;
                    cnt_len <= 0;
                    total_symbols <= 0;
                    if dht_start = '1' then
                        ready_for_data <= '1';
                    else
                        ready_for_data <= '0';
                    end if;
                    data_out_valid <= '0';
--                    cnt_len <= 1;
                    code <= (others => '0');
                    table_done <= '0';
--                    not_first <= '0';
                    
                --refresh registers
                when READ_LEN =>
                    if data_valid = '1' then
                        if byte_cnt < 1 then
                            length <= to_integer(shift_left(to_unsigned(length, 16), 8)) + to_integer(unsigned(data_in));
                        else--if byte_cnt = 1 then
                            length <= length + to_integer(unsigned(data_in));
                        end if;
                        byte_cnt <= byte_cnt + 1;
                        cnt_len <= cnt_len + 1;
                    end if;
                when READ_INFO =>
                    if data_valid = '1' then
                        byte_cnt <= 0;
                        table_id <= data_in(4) & data_in(0);
                        cnt_len <= cnt_len + 1;
                        
                    end if;
                when READ_COUNTS =>
                    if data_valid = '1' then 
                        data_out_valid <= '1';
                        huff_len <= byte_cnt;                     
                        if data_in /= x"00" then
                            min_code <= code;
                            max_code <= std_logic_vector(unsigned(code) + unsigned(data_in) - 1);
                            val_ptr <= total_symbols;
                            total_symbols <= total_symbols + to_integer(unsigned(data_in));
                            code <= std_logic_vector(shift_left(unsigned(code) + unsigned(data_in), 1));                          
                        else
                            min_code <= x"0001";
                            max_code <= x"0000";
                            code <= std_logic_vector(shift_left(unsigned(code), 1));
                        end if;
                        if byte_cnt = 15 then
                            byte_cnt <= 0;
                            data_out_valid <= '0';
--                            ready_for_data <= '0';
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
--                when FIND_LEN =>
--                    if counts(byte_cnt) = 0 then
--                        byte_cnt <= byte_cnt + 1;
--                        if not_first = '1' then
--                            if pending_increment = '1' then
--                                code <= std_logic_vector(shift_left(unsigned(code) + 1, 1));
--                                pending_increment <= '0'; 
--                            else
--                                code <= std_logic_vector(shift_left(unsigned(code), 1));
--                            end if;
--                        end if;
--                    else
--                        ready_for_data <= '1';
--                    end if;
                when READ_SYMBOL =>
                    if data_valid = '1' then
                        data_out_valid <= '1';
                        huff_val <= data_in;
                        if cnt_len = length - 1 then
                            ready_for_data <= '0';
                        end if;
--                        table_addr <= code;
--                        if counts(byte_cnt) = 1 then
--                            pending_increment <= '1';
--                            ready_for_data <= '0';
--                        else
--                            code <= std_logic_vector(unsigned(code) + 1);
--                        end if;
--                        counts(byte_cnt) <= counts(byte_cnt) - 1;
                        cnt_len <= cnt_len + 1;
--                        not_first <= '1';
                    end if; 
                when DONE =>
                    table_done <= '1';
                    ready_for_data <= '0';
                    data_out_valid <= '0';
                end case;
            end if;
        end if;
    end process;
end Behavioral;