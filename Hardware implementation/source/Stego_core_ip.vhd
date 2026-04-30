library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity Stego_core_ip is
    generic(
    DATA_WIDTH: integer :=32
--    ADDR_WIDTH: integer :=5
    );
  Port (
        clk: in std_logic;
        rst: in std_logic;
        
        mode: in std_logic_vector(3 downto 0);
        emb_bit: in std_logic;
        start: in std_logic;
        
        data_in: in std_logic_vector(DATA_WIDTH-1 downto 0);
        data_in_valid: in std_logic;
        data_in_last: in std_logic;
        data_in_ready: out std_logic;
        
        data_out: out std_logic_vector(DATA_WIDTH-1 downto 0);
        data_out_valid: out std_logic;
        data_out_last: out std_logic;
        data_out_ready: in std_logic;
        
        done: out std_logic;
        busy: out std_logic );
end Stego_core_ip;

architecture Behavioral of Stego_core_ip is
constant MODE_IDLE: std_logic_vector(3 downto 0):=x"0";
constant MODE_LOAD_HUFF_TABLES: std_logic_vector(3 downto 0):=x"1";
constant MODE_DECODE_BITSTREAM: std_logic_vector(3 downto 0):=x"2";
constant MODE_EMBED: std_logic_vector(3 downto 0):=x"3";
constant MODE_ENCODE: std_logic_vector(3 downto 0):= x"4";

signal current_mode: std_logic_vector(3 downto 0);
signal s_start: std_logic;
signal s_busy: std_logic:= '0';
signal s_done: std_logic:='0';

signal start_hload: std_logic;
signal start_decode: std_logic;
signal start_embed: std_logic;
signal start_encode: std_logic;

signal done_hload: std_logic;
signal done_decode: std_logic;
signal done_embed: std_logic;
signal done_encode: std_logic;

signal decode_data_out: std_logic_vector(DATA_WIDTH-1 downto 0);
signal decode_data_out_valid: std_logic;
signal decode_data_out_last: std_logic;
signal decode_data_in_ready: std_logic;

signal embed_data_out: std_logic_vector(DATA_WIDTH-1 downto 0);
signal embed_data_out_valid: std_logic;
signal embed_data_out_last: std_logic;
signal embed_data_in_ready: std_logic;

signal encode_data_out: std_logic_vector(DATA_WIDTH-1 downto 0);
signal encode_data_out_valid: std_logic;
signal encode_data_out_last: std_logic;
signal encode_data_in_ready: std_logic;

signal hload_in_ready: std_logic;

signal min_code: std_logic_vector(15 downto 0);
signal max_code: std_logic_vector(15 downto 0);
signal val_ptr: integer range 0 to 255;
signal huff_len: integer range 0 to 15;
signal huff_val: std_logic_vector(7 downto 0);
signal table_id: std_logic_vector(1 downto 0);
signal counts_valid: std_logic;
signal values_valid: std_logic;
--signal huffval_idx: integer range 0 to 511:=0;

signal byte_data: std_logic_vector(7 downto 0);
signal byte_valid: std_logic;
signal byte_last: std_logic;
signal byte_ready: std_logic;
signal word_reg: std_logic_vector(31 downto 0);
signal byte_cnt: unsigned(1 downto 0):="00";
--signal unpack_active: std_logic:='0';

begin

process(clk)
begin
    if rising_edge(clk)then
        if rst = '1' then
            s_start <= '0';
            current_mode <= MODE_IDLE;
        else
            s_start <= '0';
            if start = '1' and s_busy = '0' then
                current_mode <= mode;
                s_start <= '1';
            end if;
        end if;
    end if;
end process;

start_hload <= s_start when current_mode = MODE_LOAD_HUFF_TABLES else '0';
start_decode <= s_start when current_mode = MODE_DECODE_BITSTREAM else '0';
start_embed <= s_start when current_mode = MODE_EMBED else '0';
start_encode <= s_start when current_mode = MODE_ENCODE else '0';

s_busy <= '1' when (done_hload = '0' and current_mode = MODE_LOAD_HUFF_TABLES) or
                   (done_decode = '0' and current_mode = MODE_DECODE_BITSTREAM) or
                   (done_embed = '0' and current_mode = MODE_EMBED) or
                   (done_encode = '0' and current_mode = MODE_ENCODE)
                   else '0';

s_done <= done_hload or done_decode or done_embed or done_encode;

busy <= s_busy;
done <= s_done;

--process(clk)
--begin
--    if rising_edge(clk)then
--        if rst = '1' then
--            byte_cnt <= "00";
--            unpack_active <= '0';
--            byte_valid <= '0';
--            byte_last <= '0';
--        else
--            byte_valid <= '0';
--            byte_last <= '0';
--            if data_in_valid = '1' and unpack_active = '0' then
--                word_reg <= data_in;
--                unpack_active <= '1';
--                byte_cnt <= "00";
--            end if;
--            if unpack_active = '1' and byte_ready = '1' then
--                byte_valid <= '1';
--                if data_in_last = '1' and byte_cnt = "11" then
--                    byte_last <= '1';
--                end if;
----                byte_last <= data_in_last and (byte_cnt = "11");
--                case byte_cnt is
--                    when "00" => byte_data <= word_reg(31 downto 24);
--                    when "01" => byte_data <= word_reg(23 downto 16);
--                    when "10" => byte_data <= word_reg(15 downto 8);
--                    when "11" => byte_data <= word_reg(7 downto 0);
--                end case;
--                byte_cnt <= byte_cnt + 1;
--                if byte_cnt = "11" then
--                    unpack_active <= '0';
--                end if;
--            end if;
--        end if;
--    end if;
--end process;

--data_in_ready <= '1' when unpack_active = '0' or (unpack_active = '1' and byte_cnt = "11" and byte_ready = '1')
--                else '0';

process(clk)
begin
    if rising_edge(clk)then
        if rst = '1' then
            byte_cnt <= "00";
            byte_valid <= '0';
        elsif current_mode = MODE_LOAD_HUFF_TABLES then
            byte_valid <= '0';
            if data_in_valid = '1' then
                byte_valid <= '1';
                case byte_cnt is
                    when "00" => byte_data <= word_reg(31 downto 24);
                    when "01" => byte_data <= word_reg(23 downto 16);
                    when "10" => byte_data <= word_reg(15 downto 8);
                    when "11" => byte_data <= word_reg(7 downto 0);
                end case;
                if byte_ready = '1' then
                    if byte_cnt = "11" then
                        byte_cnt <= "00";
                    else
                        byte_cnt <= byte_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

--data_in_ready <= '1' when byte_ready = '1' and byte_cnt = "10" else '0';

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

U_embed: entity work.embedder
port map (
        clk => clk,
        rst => rst,
        start => start_embed,
        emb_bit => emb_bit,
        data_in => data_in,
        data_in_valid => data_in_valid,
        data_in_last => data_in_last,
        data_in_ready => embed_data_in_ready,
        data_out => embed_data_out,
        data_out_valid => embed_data_out_valid,
        data_out_last => embed_data_out_last,
        data_out_ready => data_out_ready,
        done => done_embed);
        
U_encode: entity work.bitstream_encoder
port map(
        clk => clk,
        rst => rst,
        start => start_encode,
        data_in => data_in,
        data_in_valid => data_in_valid,
        data_in_last => data_in_last,
        data_in_ready => encode_data_in_ready,
        data_out => encode_data_out,
        data_out_valid => encode_data_out_valid,
        data_out_last => encode_data_out_last,
        data_out_ready => data_out_ready,
        table_id => table_id,
        huff_val => huff_val,
        huff_len => huff_len,
        huff_code => min_code,
        huff_valid => values_valid,
        done => done_encode);   

process(clk)
begin
    case current_mode is
    when MODE_DECODE_BITSTREAM =>
        data_out <= decode_data_out;
        data_out_valid <= decode_data_out_valid;
        data_out_last <= decode_data_out_last;
        data_in_ready <= decode_data_in_ready;
    when MODE_EMBED =>
        data_out <= embed_data_out;
        data_out_valid <= embed_data_out_valid;
        data_out_last <= embed_data_out_last;
        data_in_ready <= embed_data_in_ready;
    when MODE_ENCODE =>
        data_out <= encode_data_out;
        data_out_valid <= encode_data_out_valid;
        data_out_last <= encode_data_out_last;
        data_in_ready <= encode_data_in_ready;
    when MODE_LOAD_HUFF_TABLES => 
        if byte_ready = '1' and byte_cnt = "10" then
            data_in_ready <= '1';
        else
            data_in_ready <= '0';
        end if;
    when others =>
        data_out <= (others => '0');
        data_out_valid <= '0';
        data_out_last <= '1';
        data_in_ready <= '1';
    end case;
end process;

end Behavioral;
