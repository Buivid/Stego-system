library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb_Koch_Zhao_block is
end entity tb_Koch_Zhao_block;

architecture sim of tb_Koch_Zhao_block is

    ---------------------------------------------------------------------------
    -- Константы и generics
    ---------------------------------------------------------------------------
    constant DATA_WIDTH   : integer := 16;
    constant P            : integer := 10;
    constant ADDR_COEF1   : integer := 45;
    constant ADDR_COEF2   : integer := 46;
    constant CLK_PERIOD   : time    := 10 ns;

    ---------------------------------------------------------------------------
    -- Сигналы
    ---------------------------------------------------------------------------
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal start          : std_logic := '0';

    signal coeff_in       : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal coeff_adr      : unsigned(5 downto 0)          := (others => '0');
    signal coeff_in_valid : std_logic := '0';

    signal bit_in         : std_logic := '1';
    signal bit_valid      : std_logic := '1';

    signal coeff_out      : signed(DATA_WIDTH-1 downto 0);
    signal out_adr        : unsigned(5 downto 0);
    signal out_valid      : std_logic;
    signal ready          : std_logic;

    ---------------------------------------------------------------------------
    -- Компонент под тест
    ---------------------------------------------------------------------------
    component Koch_Zhao_block
        generic (
            DATA_WIDTH : integer := 16;
            P          : integer := 10;
            addr_coef1 : integer := 45;
            addr_coef2 : integer := 46
        );
        port (
            clk            : in  std_logic;
            rst            : in  std_logic;
            start          : in  std_logic;
            coeff_in       : in  signed(DATA_WIDTH-1 downto 0);
            coeff_adr      : in  unsigned(5 downto 0);
            coeff_in_valid : in  std_logic;
            bit_in         : in  std_logic;
            bit_valid      : in  std_logic;
            coeff_out      : out signed(DATA_WIDTH-1 downto 0);
            out_adr        : out unsigned(5 downto 0);
            out_valid      : out std_logic;
            ready          : out std_logic
        );
    end component;

    -- Заглушка вместо настоящего Adjust_coeffs_block (для симуляции)
--    signal adjust_k1_in   : signed(15 downto 0);
--    signal adjust_k2_in   : signed(15 downto 0);
--    signal adjust_valid   : std_logic;
--    signal adjust_bit     : std_logic;
--    signal adjust_k1_out  : signed(15 downto 0) := (others=>'0');
--    signal adjust_k2_out  : signed(15 downto 0) := (others=>'0');
--    signal adjust_out_vld : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Заглушка Adjust_coeffs_block (просто добавляет небольшое смещение)
    ---------------------------------------------------------------------------
--    fake_adjust: process(clk)
--    begin
--        if rising_edge(clk) then
--            adjust_out_vld <= '0';

--            if rst = '1' then
--                adjust_k1_out <= (others=>'0');
--                adjust_k2_out <= (others=>'0');
--            elsif adjust_valid = '1' then
--                -- Простая имитация изменения (можно заменить на реальный блок)
--                adjust_k1_out <= adjust_k1_in + 256;   -- +1 в 8-м бите
--                adjust_k2_out <= adjust_k2_in - 512;   -- -2 в 7-м бите
--                adjust_bit    <= '1';
--                adjust_out_vld <= '1' after 3*CLK_PERIOD;   -- задержка 3 такта
--            end if;
--        end if;
--    end process;

    -- Подключение компонента
    uut: Koch_Zhao_block
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            P          => P,
            addr_coef1 => ADDR_COEF1,
            addr_coef2 => ADDR_COEF2
        )
        port map (
            clk            => clk,
            rst            => rst,
            start          => start,
            coeff_in       => coeff_in,
            coeff_adr      => coeff_adr,
            coeff_in_valid => coeff_in_valid,
            bit_in         => bit_in,
            bit_valid      => bit_valid,
            coeff_out      => coeff_out,
            out_adr        => out_adr,
            out_valid      => out_valid,
            ready          => ready
        );

    -- Генератор такта
    clk <= not clk after CLK_PERIOD/2;

    ---------------------------------------------------------------------------
    -- Стимул
    ---------------------------------------------------------------------------
    stim: process
        procedure send_coeff(
            adr : integer;
            val : integer
        ) is
        begin
            wait until rising_edge(clk);
            coeff_adr      <= to_unsigned(adr, 6);
            coeff_in       <= to_signed(val, DATA_WIDTH);
            coeff_in_valid <= '1';
            wait until rising_edge(clk);
            coeff_in_valid <= '0';
        end procedure;

        procedure wait_ready is
        begin
            wait until rising_edge(clk) and ready = '1';
        end procedure;

    begin
        -- Инициализация
        rst   <= '1';
        start <= '0';
        coeff_in_valid <= '0';
--        bit_in <= '0';
--        bit_valid <= '0';
        wait for 8*CLK_PERIOD;
        rst <= '0';
        wait for 12*CLK_PERIOD;

        report "? Тест 1: Запуск и пропуск до coef1";
        start <= '1';
        wait for 4*CLK_PERIOD;

        -- Пропускаем несколько коэффициентов
        for i in 0 to 45 loop
                send_coeff(i, 1000 + i*10);
            
        end loop;
        send_coeff(46, 12);
        wait until ready = '1';
        send_coeff(47, 77);
        

--        report "? Появляется coef1 (адрес 45)";
--        send_coeff(45, 20000);           -- должно начать сбор

--        report "? Продолжаем подавать коэффициенты до 46";
--        for i in 46 to 63 loop
--            if i = 46 then
--                send_coeff(i, -15000);
--                bit_in   <= '1';         -- бит, который должен быть встроен
--                bit_valid<= '1';
--            else
--                send_coeff(i, 5000 + (i-46)*100);
--            end if;
--        end loop;

--        -- После coef2 блок должен уйти в режим ожидания adjust ? выдачи
--        wait for 40*CLK_PERIOD;

--        report "? Проверяем выходной блок";
--        wait until out_valid = '1' and rising_edge(clk);

--        for i in 0 to 63 loop
--            wait until rising_edge(clk);
--            if out_valid = '1' then
--                report "out[" & integer'image(to_integer(out_adr)) & "] = " &
--                       integer'image(to_integer(coeff_out));
--            end if;
--        end loop;

--        wait until ready = '1' and rising_edge(clk);
--        report "? Блок вернулся в ready ? можно начинать новый";

--        -- Второй проход - проверка, что после завершения опять пропускает
--        report "? Тест 2: второй блок после завершения первого";
--        for i in 0 to 20 loop
--            send_coeff(i, 8000 + i*50);
--        end loop;

--        send_coeff(45, 32000);
--        send_coeff(46, -22000);
--        bit_in <= '0';
--        bit_valid <= '1';

--        wait for 80*CLK_PERIOD;

--        report "? Тест завершён";
        wait;
    end process;


    -- Окончание симуляции (можно убрать или закомментировать)
--    finish: process
--    begin
--        wait for 1200 ns;
--        report "? Конец симуляции по таймауту";
--        std.env.stop(0);
--        wait;
--    end process;

end architecture sim;