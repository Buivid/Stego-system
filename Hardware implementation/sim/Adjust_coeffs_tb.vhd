library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

------------------------------------------------------------

entity tb_Adjust_coeffs_block is
end entity tb_Adjust_coeffs_block;

------------------------------------------------------------

architecture sim of tb_Adjust_coeffs_block is

    constant CLK_PERIOD     : time := 10 ns;
    constant P_VALUE        : positive := 10;

    -- DUT signals
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '0';
    signal k1_in            : signed(15 downto 0) := (others => '0');
    signal k2_in            : signed(15 downto 0) := (others => '0');
    signal input_valid      : std_logic := '0';
    signal embed_bit        : std_logic := '0';
    signal k1_out           : signed(15 downto 0);
    signal k2_out           : signed(15 downto 0);
    signal output_valid     : std_logic;

    -- для удобного вывода в консоль
    file output_file        : text open write_mode is "stego_test_results.txt";

    procedure print_pair(
        constant msg    : in string;
        constant b      : in std_logic;
        constant k1i    : in signed(15 downto 0);
        constant k2i    : in signed(15 downto 0);
        constant k1o    : in signed(15 downto 0);
        constant k2o    : in signed(15 downto 0)
    ) is
        variable l : line;
    begin
        write(l, string'(msg & "  bit=" & std_logic'image(b)));
        write(l, string'("   in: "));
        hwrite(l, std_logic_vector(k1i), right, 6);
        write(l, string'(" , "));
        hwrite(l, std_logic_vector(k2i), right, 6);
        write(l, string'("  ? out: "));
        hwrite(l, std_logic_vector(k1o), right, 6);
        write(l, string'(" , "));
        hwrite(l, std_logic_vector(k2o), right, 6);
        writeline(output, l);
        writeline(output_file, l);
    end procedure;

begin

    -- DUT instantiation
    uut: entity work.Adjust_coeffs_block
        generic map (
            P => P_VALUE
        )
        port map (
            clk          => clk,
            rst          => rst,
            k1_in        => k1_in,
            k2_in        => k2_in,
            input_valid  => input_valid,
            embed_bit    => embed_bit,
            k1_out       => k1_out,
            k2_out       => k2_out,
            output_valid => output_valid
        );

    -- Clock generator
    clk <= not clk after CLK_PERIOD/2;

    ------------------------------------------------------------
    -- Stimulus process
    ------------------------------------------------------------
    stim_proc: process
    begin
        -- начальное состояние
        rst         <= '1';
        input_valid <= '0';
        embed_bit   <= '0';
        k1_in       <= (others => '0');
        k2_in       <= (others => '0');
        wait for 5 * CLK_PERIOD;
        rst         <= '0';
        wait for 4 * CLK_PERIOD;

        report "??? Тестбенч запущен ???";
--        writeline(output_file, string'("Тестбенч Adjust_coeffs_block   P = " & integer'image(P_VALUE)));
--        writeline(output_file, string'("---------------------------------------------------"));

        -- Тест 1: уже выполнено условие (bit=1, |k1| >> |k2|)
        wait until rising_edge(clk);
        k1_in       <= to_signed(120, 16);
        k2_in       <= to_signed(45, 16);
        embed_bit   <= '1';
        input_valid <= '1';
        wait until rising_edge(clk);
        input_valid <= '0';
        wait until rising_edge(clk);
        print_pair("Тест 1  (уже ок, bit=1) ", '1', to_signed(120,16), to_signed(45,16), k1_out, k2_out);

        -- Тест 2: нужно увеличить k1 (bit=1)
        wait for 2 * CLK_PERIOD;
        k1_in       <= to_signed(38, 16);
        k2_in       <= to_signed(52, 16);
        embed_bit   <= '1';
        input_valid <= '1';
        wait until rising_edge(clk);
        input_valid <= '0';
        wait until rising_edge(clk);
        print_pair("Тест 2  (нужно поднять k1) ", '1', to_signed(38, 16), to_signed(52, 16), k1_out, k2_out);

        -- Тест 3: bit=0, нужно увеличить k2 по модулю
        wait for 3 * CLK_PERIOD;
        k1_in       <= to_signed(77, 16);
        k2_in       <= to_signed(41, 16);
        embed_bit   <= '0';
        input_valid <= '1';
        wait until rising_edge(clk);
        input_valid <= '0';
        wait until rising_edge(clk);
        print_pair("Тест 3  (bit=0, поднять k2) ", '0', to_signed(77, 16), to_signed(41, 16), k1_out, k2_out);

        -- Тест 4: отрицательные значения
        wait for 3 * CLK_PERIOD;
        k1_in       <= to_signed(-95, 16);
        k2_in       <= to_signed(-30, 16);
        embed_bit   <= '1';
        input_valid <= '1';
        wait until rising_edge(clk);
        input_valid <= '0';
        wait until rising_edge(clk);
        print_pair("Тест 4  (оба отриц, bit=1) ", '1', to_signed(-95, 16), to_signed(-30, 16), k1_out, k2_out);

        -- Тест 5: нули
        wait for 3 * CLK_PERIOD;
        k1_in       <= to_signed(0, 16);
        k2_in       <= to_signed(0, 16);
        embed_bit   <= '1';
        input_valid <= '1';
        wait until rising_edge(clk);
        input_valid <= '0';
        wait until rising_edge(clk);
        print_pair("Тест 5  (нули, bit=1)      ", '1', to_signed(0, 16), to_signed(0, 16), k1_out, k2_out);

        -- Тест 6: уже выполнено для bit=0
        wait for 3 * CLK_PERIOD;
        k1_in       <= to_signed(22, 16);
        k2_in       <= to_signed(180, 16);
        embed_bit   <= '0';
        input_valid <= '1';
        wait until rising_edge(clk);
        input_valid <= '0';
        wait until rising_edge(clk);
        print_pair("Тест 6  (уже ок, bit=0)    ", '0', to_signed(22, 16), to_signed(180, 16), k1_out, k2_out);

        report "??? Все тесты завершены ???";
        wait for 20 * CLK_PERIOD;

        file_close(output_file);
        report "Симуляция завершена. Результаты записаны в stego_test_results.txt";
        -- stop симулятора (для моделей, поддерживающих finish)
        -- report "Остановка симулятора" severity failure;
        wait;
    end process;

end architecture sim;