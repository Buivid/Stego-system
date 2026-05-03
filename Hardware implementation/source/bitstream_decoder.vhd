library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bitstream_decoder is
  Port (
        clk: in std_logic;
        rst: in std_logic;
        start: in std_logic;
        data_in: in std_logic_vector(31 downto 0);
        data_in_valid: in std_logic;
        data_in_last: in std_logic;
        data_in_ready: out std_logic;
        data_out: out std_logic_vector(31 downto 0);
        data_out_valid: out std_logic;
        data_out_last: out std_logic;
        data_out_ready: in std_logic;
        --huffman tables signals
        min_code: in std_logic_vector(15 downto 0);
        max_code: in std_logic_vector(15 downto 0);
        val_ptr: in integer range 0 to 255;
        huff_len: in integer range 0 to 15;
        huff_val: in std_logic_vector(7 downto 0);
        table_id: in std_logic_vector(1 downto 0);
        counts_valid: in std_logic;
        values_valid: in std_logic;
        done: out std_logic);
end bitstream_decoder;

architecture Behavioral of bitstream_decoder is
type huff_min_max_type is array(0 to 15) of std_logic_vector(15 downto 0);
type huff_valptr_type is array(0 to 15) of integer range 0 to 255;--change 511 to 255
type huff_val_type is array(0 to 255) of std_logic_vector(7 downto 0);

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

signal huffval_idx: integer range 0 to 511:=0;

type state_type is (IDLE, DECODE, WRITE_BLOCK);
signal state: state_type:= IDLE;

signal coef_idx: integer range 0 to 63 := 0;
signal eob_detected: std_logic:= '0';
signal last_block: std_logic:= '0';
signal bits_available: integer range 0 to 64:= 0;
signal bits_buffer: std_logic_vector(63 downto 0);
signal current_table_id: integer range 0 to 3:=0;
signal block_id: integer range 0 to 2:= 0;

signal data_in_ready_reg: std_logic:='0'; 

type coefs_block_type is array(0 to 63) of std_logic_vector(15 downto 0);
signal current_block: coefs_block_type := (others => (others => '0'));
begin
process(clk)
variable current_table_id: integer range 0 to 3:= 0;
begin
    if rising_edge(clk)then
        if rst = '1' then
            huff_tables <= (others =>(
                min_code => (others => (others => '1')),
                max_code => (others => (others => '0')),
                val_ptr => (others => 0),
                huffval => (others => (others => '0'))));
            huffval_idx <= 0;
        else
            if counts_valid = '1' then
                current_table_id := to_integer(unsigned(table_id));
                huff_tables(current_table_id).min_code(huff_len) <= min_code;
                huff_tables(current_table_id).max_code(huff_len) <= max_code;
                huff_tables(current_table_id).val_ptr(huff_len) <= val_ptr;
                huffval_idx <= 0;
            end if;
            if values_valid = '1' then
                current_table_id := to_integer(unsigned(table_id));
                huff_tables(current_table_id).huffval(huffval_idx) <= huff_val;
                huffval_idx <= huffval_idx + 1; 
            end if;
        end if;
    end if;
end process;

process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            state <= IDLE;
        else
            case state is
            when IDLE =>
                if start = '1' then
                    state <= DECODE;
                end if;
            when DECODE =>
                if coef_idx = 63 or eob_detected = '1' then
                    state <= WRITE_BLOCK;
                end if;
            when WRITE_BLOCK =>
                if  coef_idx = 62 then
                    if last_block = '1' then
                        state <= IDLE;
                    else
                        state <= DECODE;
                    end if;
                end if;
            end case;
        end if;
    end if;
end process;

process(clk)
variable v_bit_pos: integer range 0 to 63;
variable add_bits: integer range -32 to 32:=0;
variable code: std_logic_vector(15 downto 0);
variable code_len: integer range 0 to 16;
variable huff_code: std_logic_vector(7 downto 0);
variable run_length: integer range 0 to 15:=0;
variable category: integer range 0 to 15:= 0;
variable extra_bits: unsigned(15 downto 0);
variable prev_Y_dc: signed(15 downto 0):=(others=>'0');
variable prev_Cb_dc: signed(15 downto 0):=(others=>'0');
variable prev_Cr_dc: signed(15 downto 0):=(others=>'0');
variable temp_code : std_logic_vector(15 downto 0);

begin
    if rising_edge(clk)then
        if rst = '1' then
            data_in_ready <= '0';
            data_out_valid <= '0';
            data_out_last <= '0';
        else
            case state is
            when IDLE =>
                data_in_ready <= '1';
                data_out_valid <= '0';
                data_out_last <= '0';
                done <= '0';
            when DECODE =>
                data_out_valid <= '0';
                v_bit_pos := bits_available-1;
                add_bits:=0;
                extra_bits:=(others=>'0');
--                if data_in_valid = '1' and bit_pos < 31 then
--                    bits_buffer <= bits_buffer(31 downto 0) & data_in;
--                    if data_in_last = '1' then
--                        last_block <= '1';
--                    end if;
--                    add_bits := add_bits + 32;
--                    data_in_ready <= '1';
--                else
--                    data_in_ready <= '0';
--                end if;
                if bits_available < 32 then
                    data_in_ready_reg <= '1';
                    data_in_ready <= '1';
                else 
                    data_in_ready_reg <= '0';
                end if;
--                data_in_ready <= data_in_ready_reg;
                if data_in_ready_reg = '1' and data_in_valid = '1' then
                    bits_buffer <= bits_buffer(31 downto 0) & data_in;
                    if data_in_last = '1' then
                        last_block <= '1';
                    end if;
                    add_bits := add_bits + 32;
                    data_in_ready <= '0';
                end if;
--                if bit_pos < 31 then
--                    data_in_ready <= '1';
--                    if data_in_valid = '1' then
--                        bits_buffer <= bits_buffer(31 downto 0) & data_in;
--                        if data_in_last = '1' then
--                            last_block <= '1';
--                        end if;
--                        add_bits := add_bits + 32;
--                    end if;
--                else 
--                    data_in_ready <= '0';
--                end if;
                if v_bit_pos + 1 >= 16 then
                    code_len:=0;
                    huff_code:= (others => '0');
                    for len in 1 to 16 loop
                        code := bits_buffer(v_bit_pos downto v_bit_pos-15);
                        code :=std_logic_vector(shift_right(unsigned(code), 16 - len));
                        if code >= huff_tables(current_table_id).min_code(len-1) and
                           code <= huff_tables(current_table_id).max_code(len-1) then     
                            code_len := len;
                            exit;
                        end if;
                    end loop;
                    if code_len > 0 then
                        huff_code:=huff_tables(current_table_id).huffval(
                        huff_tables(current_table_id).val_ptr(code_len-1) + 
                        to_integer(unsigned(code)) -
                        to_integer(unsigned(huff_tables(current_table_id).min_code(code_len-1))));
                        v_bit_pos := v_bit_pos - code_len;
                        add_bits := add_bits - code_len;
--                            bits_available <= bits_available - code_len;
                        run_length := to_integer(unsigned(huff_code(7 downto 4)));
                        category := to_integer(unsigned(huff_code(3 downto 0)));
                        
                        if category > 0 then
                            if v_bit_pos + 1 >= category then --bits_available >= category then--bits_ava меняется в этом же процессе
                                extra_bits := resize(extra_bits(15 downto category) & unsigned(bits_buffer(v_bit_pos downto v_bit_pos-category + 1)), 16);
                                v_bit_pos := v_bit_pos - category;
                                add_bits := add_bits - category;
                                if extra_bits(category-1) = '0' then
                                    extra_bits := extra_bits - (2**category - 1 );                
                                end if;
                          else
                                null;
                            end if;
                        else
                            extra_bits := (others => '0');
                        end if;
                        if coef_idx = 0 then
                            if block_id = 0 then
                                prev_Y_dc:= prev_Y_dc + signed(extra_bits);
                                current_block(coef_idx) <= std_logic_vector(prev_Y_dc);
                            elsif block_id = 1 then
                                prev_Cb_dc := prev_Cb_dc + signed(extra_bits);
                                current_block(coef_idx) <= std_logic_vector(prev_Cb_dc);
                            else
                                prev_Cr_dc := prev_Cr_dc + signed(extra_bits);
                                current_block(coef_idx) <= std_logic_vector(prev_Cr_dc);
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
                                if coef_idx < 64 then
                                    current_block(coef_idx + run_length) <= std_logic_vector(extra_bits);
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
--                            data_out_valid <= '1';
                        end if;   
                    end if;
                end if;
                bits_available <= bits_available + add_bits;
            when WRITE_BLOCK =>
                data_out <= current_block(coef_idx) & current_block(coef_idx + 1);
                data_out_valid <= '1';
                if last_block = '1' and coef_idx = 62 then
                    data_out_last <= '1';
                    done <= '1';
                end if;
                if data_out_ready = '1' then
                    if coef_idx < 62 then
                        coef_idx <= coef_idx + 2;
                    else
                        coef_idx <= 0;
                        current_block <= (others => (others => '0'));
                    end if;
                end if;
            end case;
        end if;
    end if;
end process;
end Behavioral;
