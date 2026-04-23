library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_module is
    Port (
        clk           : in  STD_LOGIC;
        rst           : in  STD_LOGIC;
        
        -- AXI-Stream Slave (от DMA)
        data_in  : in  STD_LOGIC_VECTOR(31 downto 0);
        data_in_valid : in  STD_LOGIC;
        ready_in : out STD_LOGIC;
        
        data_out: out std_logic_vector(31 downto 0);
        data_out_valid: out std_logic;
        ready_out: in std_logic);
        
end top_module;

architecture Behavioral of top_module is
component dht_parser
    Port (
        clk             : in  STD_LOGIC;
        rst             : in  STD_LOGIC;
        data_in         : in  STD_LOGIC_VECTOR(7 downto 0);
        data_valid      : in  STD_LOGIC;
        data_out_valid  : out std_logic;
        dht_start       : in  STD_LOGIC;
        min_code        : out std_logic_vector(15 downto 0);
        max_code        : out std_logic_vector(15 downto 0);
        val_ptr         : out integer range 0 to 256;
        huff_len        : out integer range 0 to 15;
        huff_val        : out std_logic_vector(7 downto 0);
        table_id        : out std_logic_vector(1 downto 0);
        table_done      : out STD_LOGIC;
        ready_for_data  : out std_logic
    );
end component;

    type state_type is (IDLE, FIND_MARKER, STORE_DHT, SKIP_SOS_HEADER, DECODE_SOS, WRITE_BLOCK, DONE);--,  WRITE_DMA);--, READ_LENGTH
    signal state : state_type := IDLE;
    
    type huff_min_max_type is array(0 to 15) of std_logic_vector(15 downto 0);
    type huff_valptr_type is array(0 to 15) of integer range 0 to 511;
    type huff_val_type is array(0 to 511) of std_logic_vector(7 downto 0);
    
    type huff_table_type is record
        min_code: huff_min_max_type;
        max_code: huff_min_max_type;
        val_ptr: huff_valptr_type;
        huffval: huff_val_type;
    end record;
    
    type huff_tables_type is array(0 to 3) of huff_table_type;
    
    signal huff_tables: huff_tables_type:=(others =>(
    min_code => (others => (others => '1')),
    max_code => (others => (others => '0')),
    val_ptr => (others => 0),
    huffval => (others => (others => '0'))));
    
    signal current_table_id : integer range 0 to 3:=0;
    signal huffval_idx: integer range 0 to 511:=0;
    
    signal dht_data_valid: std_logic:='0';
    signal dht_ready: std_logic;
    signal dht_start: std_logic:='0';
--    signal dht_data_in: std_logic_vector(7 downto 0);
    signal min_code: std_logic_vector(15 downto 0);
    signal max_code: std_logic_vector(15 downto 0);
    signal val_ptr: integer range 0 to 256;
    signal huff_len: integer range 0 to 15;
    signal huff_val: std_logic_vector(7 downto 0);
    signal table_id: std_logic_vector(1 downto 0);
    signal dht_done: std_logic;
    signal dht_ready_for_data: std_logic;
    signal dht_out_valid: std_logic;
   
   --SOS signals
   signal SOS_bit_buffer: std_logic_vector(63 downto 0):=(others => '0');
   signal bits_available: integer range 0 to 64:= 0;
   signal bit_pos: integer range 0 to 63:= 0;
   type coefs_block_type is array(0 to 63) of signed(15 downto 0); 
   signal current_block: coefs_block_type := (others => (others => '0'));
   signal coef_idx: integer range 0 to 63 := 0;
   signal prev_dc: signed(15 downto 0):=(others => '0');
   signal eob_detected: std_logic:= '0';
   signal SOS_header_length: integer range 0 to 13:= 0;
   signal SOS_byte_cnt: integer range 0 to 13:= 0;
   signal block_id: integer range 0 to 2:= 0;
    
    
   signal write_idx: integer range 0 to 63:=0;
   --сигналы для проверки декодирования коэфф
   signal lencode: integer range 0 to 16;
    -- Сигналы для сдвигового регистра
--    signal shift_reg : std_logic_vector(63 downto 0);
--    signal bit_ptr   : integer range 0 to 63;

    -- Массив для блока 8x8 (64 коэффициента по 12-16 бит)
--    type block_8x8 is array (0 to 63) of std_logic_vector(15 downto 0);
--    signal current_block : block_8x8;
--    signal coef_idx : integer range 0 to 63;

    signal data_reg: std_logic_vector(31 downto 0):=(others => '0');
    signal prev_byte: std_logic_vector(7 downto 0);
    signal byte_cnt: natural range 0 to 3 := 0;
    signal current_byte: std_logic_vector(7 downto 0);
begin
with byte_cnt select
    current_byte <= data_reg(31 downto 24) when 0,
                    data_reg(23 downto 16) when 1,
                    data_reg(15 downto 8) when 2,
                    data_reg(7 downto 0) when 3;
uut: dht_parser
port map (
        clk => clk,
        rst => rst,
        data_in => current_byte,
        data_valid => dht_data_valid,
        dht_start => dht_start,
        data_out_valid => dht_out_valid,
        min_code => min_code,    
        max_code => max_code,     
        val_ptr => val_ptr,       
        huff_len => huff_len,       
        huff_val => huff_val,       
        table_id => table_id,
        table_done => dht_done,
        ready_for_data => dht_ready_for_data
    );
    
    process(clk)
    begin
    if rising_edge(clk) then
        if rst = '1' then
            state <= IDLE;
        else
            case state is
            when IDLE =>
                if data_in_valid = '1' then
                    state <= FIND_MARKER;
                end if;
            when FIND_MARKER =>
                if data_reg(31 downto 16) = x"FFC4" or data_reg(15 downto 0) = x"FFC4" or 
                   data_reg(23 downto 8) = x"FFC4" or (prev_byte = x"FF" and data_reg(31 downto 24) = x"C4") then
                    state <= STORE_DHT;
                elsif data_reg(31 downto 16) = x"FFDA" or data_reg(15 downto 0) = x"FFDA" or data_reg(23 downto 8) = x"FFDA" then
                    state <= SKIP_SOS_HEADER;
                end if;
            when STORE_DHT =>
                if dht_done = '1' then
                    state <= FIND_MARKER;
                end if;
            when SKIP_SOS_HEADER =>
                if SOS_byte_cnt = 12 then
                    state <= DECODE_SOS;
                end if;
            when DECODE_SOS => 
                if coef_idx = 63 or eob_detected = '1' then
                    state <= WRITE_BLOCK;
                end if;
--                if eob_detected = '1' then
--                    state <= DONE;
--                elsif coef_idx = 63 then
--                    state <= WRITE_BLOCK;
--                end if;
            when WRITE_BLOCK =>
                if write_idx = 62 then
                    state <= DECODE_SOS;
                end if;
--                state <= DECODE_SOS;
            when DONE =>
                state <= IDLE; --как в это состояние перейти
            end case;
        end if;
    end if;    
    end process;
    
    process(clk)
    variable code: std_logic_vector(15 downto 0);
    variable code_len: integer range 0 to 16;
    variable huff_code: std_logic_vector(7 downto 0);
    variable run_length: integer range 0 to 15:=0;
    variable category: integer range 0 to 15:= 0;
    variable extra_bits: unsigned(15 downto 0);
    variable prev_Y_dc: signed(15 downto 0):=(others=>'0');
    variable prev_Cb_dc: signed(15 downto 0):=(others=>'0');
    variable prev_Cr_dc: signed(15 downto 0):=(others=>'0');
--    variable slice_len : integer range 0 to 16;
    variable temp_code : std_logic_vector(15 downto 0);
    variable bit_pos: integer range 0 to 63:= 0; 
    variable added_bits: integer range -32 to 32:=0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ready_in <= '0';
                byte_cnt <= 0;
                --refresh registers
            else
                case state is
                when IDLE =>
                    ready_in <= '1';
                    byte_cnt <= 0;
                    dht_data_valid <= '0';
                    data_out_valid <= '0';
                    if data_in_valid = '1' then
                        data_reg <= data_in;
                    end if;
                when FIND_MARKER =>
                    if data_in_valid = '1' then--добавить ситуацию когда FF и C4 в разных пакетах
--                        data_reg <= data_in;--что тут надо решить data_in / data_reg
                        if data_in(31 downto 16) = x"FFC4" or data_in(15 downto 0) = x"FFC4" or data_in(23 downto 8) = x"FFC4" or 
                           data_in(31 downto 16) = x"FFDA" or data_in(15 downto 0) = x"FFDA" or data_in(23 downto 8) =x"FFDA" then
                            ready_in <= '0';
--                            dht_start <= '1';
                        end if;
                        if data_reg(31 downto 16) = x"FFC4" or data_reg(15 downto 0) = x"FFC4" or data_reg(23 downto 8) = x"FFC4" or 
                        (prev_byte = x"FF" and data_reg(31 downto 24) = x"C4") then
                            dht_start <= '1';
                            dht_data_valid <= '1';
--                            ready_in <= '0';
                            if data_reg(31 downto 16) = x"FFC4" then
                                byte_cnt <= 2; --если со второго то с длиной опять будут проблемы
                            elsif data_reg(23 downto 8) = x"FFC4" then
                                byte_cnt <= 3;
                            elsif (prev_byte = x"FF" and data_reg(31 downto 24) = x"C4") then
                                byte_cnt <= 1;
                            elsif data_reg(15 downto 0) = x"FFC4" then
                                byte_cnt <= 0;
                                data_reg <= data_in;
                                ready_in <= '1';
                            end if;
                        elsif data_reg(31 downto 16) = x"FFDA" then
                            byte_cnt <= 2;
                        elsif data_reg(23 downto 8) = x"FFDA" then 
                            byte_cnt <= 3;
                        elsif data_reg(15 downto 0) = x"FFDA" then
                            byte_cnt <= 0;
                            data_reg <= data_in;
                            ready_in <= '1';            
                        else
                            data_reg <= data_in;
                            prev_byte <= data_reg(7 downto 0);
                        end if;                                             
                    end if;
                when STORE_DHT =>
                    dht_start <= '0';
                    if data_in_valid = '1' then
--                        if dht_done
                        dht_data_valid <= '1';
                        if dht_ready_for_data = '1' then
                            if byte_cnt < 3 then
                                byte_cnt <= byte_cnt + 1;
                                ready_in <= '0';
                            else
                                data_reg <= data_in;
                                prev_byte <= data_reg(7 downto 0);
                                byte_cnt <= 0;
                                ready_in <= '1';
                            end if;
                        else 
                            ready_in <= '0';
                        end if;
                    else
                        dht_data_valid <= '0';
                    end if;
                    current_table_id <= to_integer(unsigned(table_id));
                    if dht_out_valid = '1' then         
                        if huff_len < 15 then
                            huffval_idx <= 0;
                            huff_tables(current_table_id).min_code(huff_len) <= min_code;
                            huff_tables(current_table_id).max_code(huff_len) <= max_code;
                            huff_tables(current_table_id).val_ptr(huff_len) <= val_ptr;
                        else
                            huff_tables(current_table_id).huffval(huffval_idx) <= huff_val;
                            huffval_idx <= huffval_idx + 1;
                        end if;
                    end if;
                when SKIP_SOS_HEADER =>
                    current_table_id <= 0;
                    block_id <= 0;
                    if data_in_valid = '1' then
                        if SOS_byte_cnt < 12 then
                            SOS_byte_cnt <= SOS_byte_cnt + 1;
                            if byte_cnt < 3 then
                                byte_cnt <= byte_cnt + 1;
                                ready_in <= '0';
                            else
                                data_reg <= data_in;
                                SOS_bit_buffer <= SOS_bit_buffer(31 downto 0) & data_in;
--                                bits_available <= 64;
                                byte_cnt <= 0;
                                ready_in <= '1';
                            end if;
                        else
                            SOS_bit_buffer <= SOS_bit_buffer(31 downto 0) & data_in;  
                            ready_in <= '1';
                            byte_cnt <= 0;
                            if byte_cnt = 0 then
                                bits_available <= 64;
                                bit_pos := 63;
                            elsif byte_cnt = 1 then
                                bits_available <= 56;
                                bit_pos := 55;
                            elsif byte_cnt = 2 then
                                bits_available <= 48;
                                bit_pos := 47;
                            elsif byte_cnt = 3 then
                                bits_available <= 40;
                                bit_pos := 39;  
                            end if;                          
                        end if;
                    end if;
                when DECODE_SOS =>
                    --byte_cnt points on correct current_byte in data_reg
--                    ready_in <= '0';
                    data_out_valid <= '0';
                    bit_pos := bits_available - 1;
                    added_bits:=0;
                    extra_bits:=(others=>'0');

                    if bit_pos + 1 < 32 and data_in_valid = '1' then
                        if SOS_bit_buffer(7 downto 0) = x"FF" and data_in(31 downto 24) = x"00" then --if FF 00 00 удалится пол инфа
                            SOS_bit_buffer <= SOS_bit_buffer(39 downto 0) & data_in(23 downto 0);
                            added_bits := added_bits + 24;
                        elsif data_in(31 downto 16) = x"FF00" then
                            SOS_bit_buffer <= SOS_bit_buffer(39 downto 0) & data_in(31 downto 24) & data_in(15 downto 0);
                            added_bits := added_bits + 24;
                        elsif data_in(23 downto 8) = x"FF00" then
                            SOS_bit_buffer <= SOS_bit_buffer(39 downto 0) & data_in(31 downto 16) & data_in(7 downto 0);
                            added_bits := added_bits + 24;
                        elsif data_in(15 downto 0) = x"FF00" then
                            SOS_bit_buffer <= SOS_bit_buffer(39 downto 0) & data_in(31 downto 8);
                            added_bits := added_bits + 24;
                        else
                            SOS_bit_buffer <= SOS_bit_buffer(31 downto 0) & data_in;
                            added_bits := added_bits + 32;        
                        end if;                      
                        ready_in <= '1';
                    else
                        ready_in <= '0';                 
                    end if;
                    if bit_pos + 1 >= 16 then
                        code:=SOS_bit_buffer(bit_pos downto bit_pos-15);
                        code_len:=0;
                        huff_code := (others => '0');
                        for len in 1 to 16 loop  
--                            := len;                      
                            temp_code := code;                    -- копируем
--                            temp_code := temp_code(15 downto 16-len);  -- срез
                            temp_code := std_logic_vector(shift_right(unsigned(temp_code),16 - len));
                            if temp_code >= huff_tables(current_table_id).min_code(len-1) and
                               temp_code <= huff_tables(current_table_id).max_code(len-1) then
                                
                                code_len := len;
                                exit;
                            end if;
                        end loop;                        
--                        for len in 1 to 16 loop
--                            if code(15 downto 16-len) >= huff_tables(current_table_id).min_code(len-1) and
--                               code(15 downto 16-len) <= huff_tables(current_table_id).max_code(len-1) then
----                                code_len := len;
--                                lencode <= len;
--                                exit;
--                            end if;
--                        end loop;
                        if code_len > 0 then
                            huff_code:=huff_tables(current_table_id).huffval(
                            huff_tables(current_table_id).val_ptr(code_len-1) + 
                            to_integer(unsigned(code(15 downto 16-code_len))) -
                            to_integer(unsigned(huff_tables(current_table_id).min_code(code_len-1))));
--                            SOS_bit_buffer <= std_logic_vector(shift_left(unsigned(SOS_bit_buffer), code_len));
                            bit_pos := bit_pos - code_len;
                            added_bits := added_bits - code_len;
--                            bits_available <= bits_available - code_len;
                            run_length := to_integer(unsigned(huff_code(7 downto 4)));
                            category := to_integer(unsigned(huff_code(3 downto 0)));
                            
                            if category > 0 then
                                if bit_pos + 1 >= category then --bits_available >= category then--bits_ava меняется в этом же процессе
--                                    extra_bits := unsigned(SOS_bit_buffer(bit_pos downto bit_pos-15));
--                                    extra_bits := unsigned(shift_right(extra_bits, 16 - category));
                                    extra_bits := resize(extra_bits(15 downto category) & unsigned(SOS_bit_buffer(bit_pos downto bit_pos-category + 1)), 16);
                                    bit_pos := bit_pos - category;
                                    added_bits := added_bits - category;
                                    if extra_bits(category-1) = '0' then
                                        extra_bits := extra_bits - (2**category - 1 );                
                                    end if;
--                                    SOS_bit_buffer <= std_logic_vector(shift_left(unsigned(SOS_bit_buffer), category));
--                                    bits_available <= bits_available - category;
                                else
                                    --не хватает бит
                                    null;
                                end if;
                            else
                                extra_bits := (others => '0');
                            end if;
                            if coef_idx = 0 then
                                if block_id = 0 then
                                    prev_Y_dc:= prev_Y_dc + signed(extra_bits);
                                    current_block(coef_idx) <= prev_Y_dc;
                                elsif block_id = 1 then
                                    prev_Cb_dc := prev_Cb_dc + signed(extra_bits);
                                    current_block(coef_idx) <= prev_Cb_dc;
                                else
                                    prev_Cr_dc := prev_Cr_dc + signed(extra_bits);
                                    current_block(coef_idx) <= prev_Cr_dc;
                                end if;
--                                prev_dc := prev_dc + signed(extra_bits);
--                                current_block(coef_idx) <= prev_dc;
                                coef_idx <= coef_idx + 1;
                                if block_id = 0 then
                                    current_table_id <= 2;
                                else
                                    current_table_id <= 3;
                                end if;
                            else
                                if run_length = 15 and category = 0 then
                                    coef_idx <= coef_idx + 16;
                                elsif run_length = 0 and category = 0 then
                                    eob_detected <= '1';
                                    coef_idx <= 63;
                                else
--                                    for i in 1 to run_length loop
--                                        if coef_idx < 63 then
--                                            coef_idx <= coef_idx + 1;
--                                        end if;
--                                    end loop;
                                    if coef_idx < 64 then
                                        current_block(coef_idx + run_length) <= signed(extra_bits);
                                        coef_idx <= coef_idx + 1 + run_length;
                                    end if;
                                end if;
                            end if;
                            if coef_idx = 63 or eob_detected = '1' then
                                coef_idx <= 0;
                                eob_detected <= '0';
                                if block_id = 0 then
                                    block_id <= 1;
                                    current_table_id <= 1;
                                elsif block_id = 1 then
                                    block_id <= 2;
                                    current_table_id <= 1;
                                else
                                    block_id <= 0;
                                    current_table_id <= 0;
                                end if;
                                data_out_valid <= '1';
                            end if;
                        end if;
                    end if;
                    bits_available <= bits_available + added_bits;
                when WRITE_BLOCK =>
                    
                    data_out <= std_logic_vector(current_block(write_idx)) &  std_logic_vector(current_block(write_idx+1));
                    if ready_out = '1' then
                        if write_idx < 62 then
                            write_idx <= write_idx + 2;
                        else
                            write_idx <= 0;
--                            data_out_valid <= '0';
                            current_block <= (others => (others => '0'));    
                        end if;
                    end if;
                when DONE =>
                    data_out_valid <= '1';
                end case;
            end if;
        end if;
    end process;
    
--    process(clk)
--    begin
--        if rising_edge(clk) then
--            if rst = '1' then
--                state <= IDLE;
--                ready_in <= '0';
--                byte_cnt <= 0;
--            else
--                case state is
--                    when IDLE =>
--                        ready_in <= '1';
--                        if data_in_valid = '1' then
--                            data_reg <= data_in;
----                            ready_in <= '0';
--                            state <= FIND_MARKER;
--                        end if;

--                    when FIND_MARKER =>
--                        -- Поиск FF C4 (DHT) или FF DA (SOS)
--                        data_reg <= data_in;
--                        if data_reg(31 downto 16) = x"FFC4" then
--                            state <= STORE_DHT;
--                            byte_cnt <= 0;
--                            ready_in <= '0';
----                            ready_in <= '0';
----                            dht_shift <= '1';
----                        elsif data_in(31 downto 16) = x"FFDA" then
----                            state <= DECODE_SOS;
--                        end if;

--                    when STORE_DHT =>
--                        dht_start <= '1';
--                        dht_data_in <= data_reg(31 downto 24);
--                        if byte_cnt < 3 then
--                            byte_cnt <= byte_cnt + 1;
--                            ready_in <= '0';
--                        else
--                            byte_cnt <= 0;
--                            ready_in <= '1';
--                            if data_in_valid = '1' then
--                                data_reg <= data_in;
----                                ready_in <= '0';
----                            else
----                                ready_in <= '1';
--                            end if;
--                        end if;
----                    when DECODE_SOS =>
----                        -- Основной цикл декодирования
----                        -- 1. Извлечь код Хаффмана из shift_reg
----                        -- 2. Найти категорию (Magnitude)
----                        -- 3. Считать дополнительные биты
----                        -- 4. Записать в current_block[zigzag_idx]
                        
----                        if coef_idx = 63 then
----                            state <= WRITE_DMA;
----                        end if;

----                    when WRITE_DMA =>
----                        -- Передача блока 8x8 через AXI-Stream на выход
----                        data_out(15 downto 0) <= current_block(coef_idx);
----                        data_out_valid <= '1';
----                        if ready_out = '1' then
----                            if coef_idx = 63 then
----                                state <= DECODE_SOS; -- К следующему блоку
----                            end if;
----                        end if;
--                end case;
--            end if;
--        end if;
--    end process;
    
--process(clk)
--begin
--if rising_edge(clk) then
--    if rst = '1' then
--        data_reg <= (others => '0');
--        byte_cnt <= 0;
--        ready_in <= '1';
--    elsif dht_shift = '1' then        
--        if byte_cnt = 3 then
--            byte_cnt <= 0;
--            ready_in <= '0';
--            data_reg <= data_in;
--        elsif byte_cnt = 2 then
--            ready_in <= '1';
--        else
--            ready_in <= '0';
--            byte_cnt <= byte_cnt + 1;
--            data_reg <= std_logic_vector(shift_left(unsigned(data_reg), 8));
--        end if;
--    else
--        ready_in <= '1';
----        data_reg(31 downto 0) <= data_in;
--    end if;
--end if;
--end process;
end Behavioral;
