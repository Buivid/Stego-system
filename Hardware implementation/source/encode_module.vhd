library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
--добавить байт стаффинг и дополнение до байта в конце файла
entity encode_module is
port(
        clk: in std_logic;
        rst: in std_logic;
        
        --axi huffman tables
        s_axis_huff_tdata: in std_logic_vector(31 downto 0);
        s_axis_huff_tvalid: in std_logic;
        s_axis_huff_tready: out std_logic;
        s_axis_huff_tlast: in std_logic;
        
        --axi coefficients
        s_axis_coefs_tdata: in std_logic_vector(31 downto 0);
        s_axis_coefs_tvalid: in std_logic;
        s_axis_coefs_tready: out std_logic;
        s_axis_coefs_tlast: in std_logic;
        
        --axi output jpeg bitstream
        m_axis_out_tdata: out std_logic_vector(31 downto 0);
        m_axis_out_tvalid: out std_logic;
        m_axis_out_tready: in std_logic;
        m_axis_out_tlast: out std_logic
        );
--        data_in: in std_logic_vector(31 downto 0);
--        data_in_valid: in std_logic;
--        ready_in: out std_logic;
        
--        data_out: out std_logic_vector(31 downto 0);
--        data_out_valid: out std_logic;
--        ready_out: in std_logic);
end encode_module;

architecture behavioral of encode_module is
type state_type is (IDLE, LOAD_TABLES, LOAD_COEFS, ENCODE_COEFS, OUTPUT_STREAM);-- WAIT_COEFS, 
signal state: state_type:= IDLE;

--signal table_type is array(0 to 255) of std_logic_vector()
type code_array is array(0 to 255) of std_logic_vector(15 downto 0);
type len_array is array(0 to 255) of integer range 0 to 16;
type huff_table_type is record
        huffcode: code_array;
        hufflen: len_array;
    end record;
type huff_tables_type is array(0 to 3) of huff_table_type;
signal huff_tables: huff_tables_type:=(others =>(
huffcode => (others => (others => '0')),
hufflen => (others => 0)));

--type huff_mem_t is array(0 to 1023) of std_logic_vector(20 downto 0);
----4 таблицы по 256 значений: 16 бит код + 5 бит длина
--signal huff_mem: huff_mem_t;
--attribute ram_style: string;
--attribute ram_style of huff_mem: signal is "block";
--signal wr_addr: std_logic_vector(9 downto 0);
--signal wr_data: std_logic_vector(19 downto 0);
--signal rd_addr: std_logic_vector(9 downto 0);
--signal rd_data: std_logic_vector(19 downto 0);

signal h_code: std_logic_vector(15 downto 0);
signal h_len: std_logic_vector(4 downto 0);

signal tables_ready: std_logic:='0';
type block_type is array(0 to 63) of signed(15 downto 0);
signal current_block: block_type;
signal coef_cnt: integer range 0 to 64:=0;
signal coef_idx: integer range 0 to 1:= 0;
signal out_valid_int: std_logic:='0';

signal coefs: std_logic_vector(31 downto 0);
signal curr_coef: std_logic_vector(15 downto 0);
signal coef1: std_logic_vector(15 downto 0);
signal coef2: std_logic_vector(15 downto 0);
signal bitstream_buffer: std_logic_vector(0 to 63):=(others => '0');
signal bit_pos: integer range 0 to 63:=0;
signal last_coef: std_logic :='0';

signal block_id: integer range 0 to 2:=0;
signal prev_Y_dc: signed(15 downto 0):=(others=>'0');
signal prev_Cb_dc: signed(15 downto 0):=(others=>'0');
signal prev_Cr_dc: signed(15 downto 0):=(others=>'0');
begin

process(clk)
begin
if rising_edge(clk) then
    if rst = '1' then
        state <= IDLE;
    else
        case state is
        when IDLE =>
            if s_axis_huff_tvalid = '1' then
                state <= LOAD_TABLES;
            elsif s_axis_coefs_tvalid = '1' and tables_ready = '1' then
                state <= LOAD_COEFS;
            end if;
        when LOAD_TABLES =>
            if s_axis_huff_tlast = '1' then
                state <= IDLE;
            end if;
--        when WAIT_COEFS =>
--            if s_axis_coefs_tvalid = '1' and tables_ready = '1' then
--                state <= LOAD_COEFS;
--            end if;
        when LOAD_COEFS =>
            if s_axis_coefs_tvalid = '1' then
                state <= ENCODE_COEFS;
--                state <= OUTPUT_STREAM;
            end if;
        when ENCODE_COEFS =>
            if bit_pos > 31 or last_coef = '1' then
                state <= OUTPUT_STREAM;
            else
                state <= LOAD_COEFS;
            end if;
        when OUTPUT_STREAM =>
            if last_coef = '1' then
                state <= IDLE;
            elsif m_axis_out_tready = '1' then
                state <= LOAD_COEFS;
            end if; 
        end case;
    end if;
end if; 
end process;

with coef_idx select
    curr_coef <= coefs(31 downto 16) when 0,
                    coefs(15 downto 0) when 1;
process(clk)
variable h_table_id : integer range 0 to 3;
variable h_len: integer range 0 to 15;
variable h_value: integer range 0 to 255;
variable h_code: std_logic_vector(15 downto 0);

variable diff: signed(15 downto 0):=(others=>'0');
variable h_data: unsigned(15 downto 0):=(others=>'0');
variable run_length: integer range 0 to 16:=0;
variable category: integer range 0 to 16:=0;

variable v_bit_pos: integer range 0 to 63:=0;
variable v_bitstream_buffer: std_logic_vector(0 to 63):=(others => '0');
variable abs_val: unsigned(15 downto 0);

begin
if rising_edge(clk) then
    if rst = '1' then
        --refresh registers
        tables_ready <= '0';
        s_axis_huff_tready <= '0';
    else
        case state is
        when IDLE =>
            
        when LOAD_TABLES =>
            s_axis_huff_tready <= '1';
            if s_axis_huff_tvalid = '1' then
                h_table_id := to_integer(unsigned(s_axis_huff_tdata(31 downto 28)));
                h_len := to_integer(unsigned(s_axis_huff_tdata(27 downto 24)));
                h_value := to_integer(unsigned(s_axis_huff_tdata(23 downto 16)));
                h_code := s_axis_huff_tdata(15 downto 0);
--                wr_addr <= s_axis_huff_tdata(31 downto 30) & s_axis_huff_tdata(23 downto 16);
--                wr_data <= s_axis_huff_tdata(15 downto 0) & s_axis_huff_tdata(27 downto 24);
--                huff_mem(to_integer(unsigned(wr_addr))) <= wr_data;
                
                huff_tables(h_table_id).huffcode(h_value) <= h_code;
                huff_tables(h_table_id).hufflen(h_value) <= h_len;
                if s_axis_huff_tlast = '1' then
                    tables_ready <= '1';
                    s_axis_huff_tready <= '0';
                end if;                
            end if;
        when LOAD_COEFS =>
            if s_axis_coefs_tvalid = '1' then
                s_axis_coefs_tready <= '1';
                coefs <= s_axis_coefs_tdata;
--                coef1 <= s_axis_coefs_tdata(31 downto 16);
--                coef2 <= s_axis_coefs_tdata(15 downto 0);
                coef_cnt <= coef_cnt + 2;
            end if;
        when ENCODE_COEFS =>
            s_axis_coefs_tready <= '0';
            v_bitstream_buffer := bitstream_buffer;
            v_bit_pos := bit_pos;
            category:= 0;
--            --написать для dc 
            if coef_cnt = 2 and coef_idx = 0 then
                if block_id = 0 then
                    h_table_id := 0;
                    diff := signed(curr_coef) - prev_Y_dc;
                    prev_Y_dc <= signed(curr_coef);
                else 
                    h_table_id := 2;
                    if block_id = 1 then
                        diff:= signed(coef1) - prev_Cb_dc;
                        prev_Cb_dc <= signed(coef1);
                    else
                        diff:= signed(coef1) - prev_Cr_dc;
                        prev_Cr_dc <= signed(coef1);
                    end if;
                end if;
                if signed(diff) < 0 then
                    abs_val := unsigned(-signed(diff));
                else    
                    abs_val := unsigned(diff);
                end if;
                for i in 15 downto 0 loop
                    if abs_val(i) = '1' then
                        category:= i + 1;
                        exit;
                    end if;
                end loop;
                h_value:= category;
                h_code := huff_tables(h_table_id).huffcode(h_value);
                h_len := huff_tables(h_table_id).hufflen(h_value);
            
                if signed(diff) < 0 then
                    h_data := unsigned(diff) + (2**category - 1);
                else
                    h_data := unsigned(diff);
                end if; 
                for i in 0 to 15 loop
                    if i < h_len then
                        v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
                    end if;
                end loop;
                v_bit_pos := v_bit_pos + h_len;
                
                for i in 0 to 15 loop
                    if i < category then
                        v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
                    end if;
                end loop;
                v_bit_pos := v_bit_pos + category;
                if h_table_id = 0 then
                    h_table_id:= 1;
                else 
                    h_table_id:= 3;
                end if;
            else
                if signed(curr_coef) = 0 then
                    run_length:= run_length + 1;
                    if run_length = 16 then
                        h_value:= 240; --F0 --to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
                        h_code := huff_tables(h_table_id).huffcode(h_value);
                        h_len := huff_tables(h_table_id).hufflen(h_value);
--                        v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len-1) := h_code(h_len-1 downto 0);
--                        v_bit_pos := v_bit_pos + h_len;
                        for i in 0 to 15 loop
                            if i < h_len then
                                v_bitstream_buffer(v_bit_pos+i) := h_code(h_len - 1 -i);
                            end if;
                        end loop;
                        v_bit_pos := v_bit_pos + h_len;
                        run_length:= 0;
                    end if;
                else
                    if signed(curr_coef) < 0 then
                        abs_val := unsigned(-signed(curr_coef));
                    else
                        abs_val := unsigned(curr_coef);
                    end if;
                    for i in abs_val'range loop
                        if abs_val(i) = '1' then
                            category:= i + 1;
                            exit;
                        end if;
                    end loop;
                    h_value:= run_length*16 + category;--to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
                    h_code := huff_tables(h_table_id).huffcode(h_value);
                    h_len := huff_tables(h_table_id).hufflen(h_value);
                
                    if signed(curr_coef) < 0 then
                        h_data := unsigned(curr_coef) + (2**category - 1);
                    else
                        h_data := unsigned(curr_coef);
                    end if;
--                    v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len + category-1) := h_code(h_len-1 downto 0) & std_logic_vector(h_data(category-1 downto 0));
--                    v_bit_pos := v_bit_pos + h_len + category;
                    for i in 0 to 15 loop
                        if i < h_len then
                            v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
                        end if;
                    end loop;
                    v_bit_pos := v_bit_pos + h_len;
                    
                    for i in 0 to 15 loop
                        if i < category then
                            v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
                        end if;
                    end loop;
                    v_bit_pos := v_bit_pos + category;
                    run_length := 0;                                        
                end if;                            
            end if;
--            if coef_cnt = 64 then
--                if run_length > 0 then
--                    h_value := 0; -- EOB
--                    h_code := huff_tables(h_table_id).huffcode(h_value);
--                    h_len  := huff_tables(h_table_id).hufflen(h_value);        
----                    v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len-1) := h_code(h_len-1 downto 0);    
----                    v_bit_pos := v_bit_pos + h_len;
--                    for i in 0 to 15 loop
--                        if i < h_len then
--                            v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
--                        end if;
--                    end loop;
--                    v_bit_pos := v_bit_pos + h_len;
--                    run_length := 0;
--                end if; 
--                coef_cnt <= 0;
--                if block_id = 0 then
--                    block_id <= 1;
--                elsif block_id = 1 then
--                    block_id <= 2;
--                else
--                    block_id <= 0;
--                end if;
--            end if;
--            if coef_idx = 1 then
--                coef_idx <= 0;
--            else
--                coef_idx <= 1;
--            end if;
--            bitstream_buffer <= v_bitstream_buffer;
--            bit_pos <= v_bit_pos; 


--            if coef_cnt = 2 then --первый элемент дс
--                if block_id = 0 then
--                    h_table_id := 0;
--                    diff:= signed(coef1) - prev_Y_dc;
--                    prev_Y_dc := signed(coef1);
--                else 
--                    h_table_id := 2;
--                    if block_id = 1 then
--                        diff:= signed(coef1) - prev_Cb_dc;
--                        prev_Cb_dc := signed(coef1);
--                    else
--                        diff:= signed(coef1) - prev_Cr_dc;
--                        prev_Cr_dc := signed(coef1);
--                    end if;
--                end if;
--                --обнулить до этого момента run_length 
--                if signed(diff) < 0 then
--                    abs_val := unsigned(-signed(diff));
--                else    
--                    abs_val := unsigned(diff);
--                end if;
--                for i in 15 downto 0 loop
--                    if abs_val(i) = '1' then
--                        category:= i + 1;
--                        exit;
--                    end if;
--                end loop;
--                h_value:= category;-- to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
--                h_code := huff_tables(h_table_id).huffcode(h_value);
--                h_len := huff_tables(h_table_id).hufflen(h_value);
            
--                if signed(diff) < 0 then
--                    h_data := unsigned(diff) + (2**category - 1);
--                else
--                    h_data := unsigned(diff);
--                end if; 
----                v_bitstream_buffer(v_bit_pos to v_bit_pos + h_len - 1) := h_code(h_len-1 downto 0);
----                v_bit_pos := v_bit_pos + h_len;
----                v_bitstream_buffer(v_bit_pos to v_bit_pos + category - 1) := std_logic_vector(h_data(category-1 downto 0));
----                v_bit_pos := v_bit_pos + category;
--                for i in 0 to 15 loop
--                    if i < h_len then
--                        v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
--                    end if;
--                end loop;
--                v_bit_pos := v_bit_pos + h_len;
                
--                for i in 0 to 15 loop
--                    if i < category then
--                        v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
--                    end if;
--                end loop;
--                v_bit_pos := v_bit_pos + category;
--                if h_table_id = 0 then
--                    h_table_id:= 1;
--                else 
--                    h_table_id:= 3;
--                end if;
--            else
--                if signed(coef1) = 0 then
--                    run_length:= run_length + 1;
--                    if run_length = 16 then
--                        h_value:= 240; --F0 --to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
--                        h_code := huff_tables(h_table_id).huffcode(h_value);
--                        h_len := huff_tables(h_table_id).hufflen(h_value);
----                        v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len-1) := h_code(h_len-1 downto 0);
----                        v_bit_pos := v_bit_pos + h_len;
--                        for i in 0 to 15 loop
--                            if i < h_len then
--                                v_bitstream_buffer(v_bit_pos+i) := h_code(h_len - 1 -i);
--                            end if;
--                        end loop;
--                        v_bit_pos := v_bit_pos + h_len;
--                        run_length:= 0;
--                    end if;
--                else
--                    if signed(coef1) < 0 then
--                        abs_val := unsigned(-signed(coef1));
--                    else
--                        abs_val := unsigned(coef1);
--                    end if;
--                    for i in abs_val'range loop
--                        if abs_val(i) = '1' then
--                            category:= i + 1;
--                            exit;
--                        end if;
--                    end loop;
--                    h_value:= run_length*16 + category;--to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
--                    h_code := huff_tables(h_table_id).huffcode(h_value);
--                    h_len := huff_tables(h_table_id).hufflen(h_value);
                
--                    if signed(coef1) < 0 then
--                        h_data := unsigned(coef1) + (2**category - 1);
--                    else
--                        h_data := unsigned(coef1);
--                    end if;
----                    v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len + category-1) := h_code(h_len-1 downto 0) & std_logic_vector(h_data(category-1 downto 0));
----                    v_bit_pos := v_bit_pos + h_len + category;
--                    for i in 0 to 15 loop
--                        if i < h_len then
--                            v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
--                        end if;
--                    end loop;
--                    v_bit_pos := v_bit_pos + h_len;
                    
--                    for i in 0 to 15 loop
--                        if i < category then
--                            v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
--                        end if;
--                    end loop;
--                    v_bit_pos := v_bit_pos + category;
--                    run_length := 0;                                        
--                end if;               
--            end if;
--            if signed(coef2) = 0 then
--                run_length:= run_length + 1;
--                if run_length = 16 then
--                    h_value:= 240; --F0 --to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
--                    h_code := huff_tables(h_table_id).huffcode(h_value);
--                    h_len := huff_tables(h_table_id).hufflen(h_value);
----                    v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len-1) := h_code(h_len-1 downto 0);
----                    v_bit_pos := v_bit_pos + h_len;
--                    for i in 0 to 15 loop
--                        if i < h_len then
--                            v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
--                        end if;
--                    end loop;
--                    v_bit_pos := v_bit_pos + h_len;
--                    run_length:= 0;
--                end if;
--            else
--                if signed(coef2) < 0 then
--                    abs_val := unsigned(-signed(coef2));
--                else
--                    abs_val := unsigned(coef2);
--                end if;
--                for i in abs_val'range loop
--                    if abs_val(i) = '1' then
--                        category:= i + 1;
--                        exit;
--                    end if;
--                end loop;
--                h_value:= run_length*16 + category;--to_integer(to_unsigned(run_length, 8) & to_unsigned(category, 8));
--                h_code := huff_tables(h_table_id).huffcode(h_value);
--                h_len := huff_tables(h_table_id).hufflen(h_value);
            
--                if signed(coef2) < 0 then
--                    h_data := unsigned(coef2) + (2**category - 1);
--                else
--                    h_data := unsigned(coef2);
--                end if;
----                v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len + category-1) := h_code(h_len-1 downto 0) & std_logic_vector(h_data(category-1 downto 0));
----                v_bit_pos := v_bit_pos + h_len + category; 
--                for i in 0 to 15 loop
--                    if i < h_len then
--                        v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
--                    end if;
--                end loop;
--                v_bit_pos := v_bit_pos + h_len;
                
--                for i in 0 to 15 loop
--                    if i < category then
--                        v_bitstream_buffer(v_bit_pos + i) := h_data(category - 1 - i);
--                    end if;
--                end loop;
--                v_bit_pos := v_bit_pos + category;
--                run_length := 0;                                       
--            end if; 
--            if coef_cnt = 64 then
--                if run_length > 0 then
--                    h_value := 0; -- EOB
--                    h_code := huff_tables(h_table_id).huffcode(h_value);
--                    h_len  := huff_tables(h_table_id).hufflen(h_value);        
----                    v_bitstream_buffer(v_bit_pos to v_bit_pos+h_len-1) := h_code(h_len-1 downto 0);    
----                    v_bit_pos := v_bit_pos + h_len;
--                    for i in 0 to 15 loop
--                        if i < h_len then
--                            v_bitstream_buffer(v_bit_pos + i) := h_code(h_len - 1 - i);
--                        end if;
--                    end loop;
--                    v_bit_pos := v_bit_pos + h_len;
--                    run_length := 0;
--                end if; 
--                coef_cnt <= 0;
--                if block_id = 0 then
--                    block_id <= 1;
--                elsif block_id = 1 then
--                    block_id <= 2;
--                else
--                    block_id <= 0;
--                end if;
--            end if;
--            bitstream_buffer <= v_bitstream_buffer;
--            bit_pos <= v_bit_pos;         

        when OUTPUT_STREAM =>
            if m_axis_out_tready = '1' then
                 m_axis_out_tdata <= bitstream_buffer(0 to 31);
                 m_axis_out_tvalid <= '1';
                 bitstream_buffer <= bitstream_buffer(32 to 63) & x"00000000";
                 bit_pos <= bit_pos - 32;
            end if;
        end case;
    end if;
end if;
end process;
end behavioral;