// -----------------------------------------------------------------------------
// DE1_SoC — Top-Level Connect Four System
// -----------------------------------------------------------------------------
// Responsibilities:
// - Generate divided clocks for pacing and LED scanning.
// - Handle input synchronization, debouncing, and edge detection for keys/switches.
// - Maintain cursor position for human player.
// - Instantiate datapath, controller, and display modules.
// - Drive HEX displays for current player, winner marquee, and draw.
// - Provide diagnostic LEDs.
// -----------------------------------------------------------------------------
module DE1_SoC (
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, // Seven-seg displays
    output logic [9:0] LEDR,                               // Diagnostic LEDs
    input  logic [3:0] KEY,                                // Pushbuttons
    input  logic [9:0] SW,                                 // Slide switches
    output logic [35:0] GPIO_1,                            // LED matrix GPIO
    input  logic CLOCK_50                                  // 50 MHz system clock
);

    // =========================================================================
    // Clock Divider and Derived Signals
    // =========================================================================
    logic [31:0] clk;
    logic        SYSTEM_CLOCK;   // ~1.5 kHz for LED scanning
    logic        game_enable;    // ~12 Hz pacing for controller/game
    logic        blink;          // Slow blink (~1–2 Hz) for cursor animation

    clock_divider divider (.clock(CLOCK_50), .divided_clocks(clk));

    assign SYSTEM_CLOCK = clk[14];
    assign game_enable  = clk[22];
    assign blink        = clk[25];

    // =========================================================================
    // LED Matrix Driver (16×16)
    // =========================================================================
    logic [15:0][15:0] RedPixels;
    logic [15:0][15:0] GrnPixels;
    logic              RST;

    assign RST = SW[9]; // Slide switch reset (active-high)

    LEDDriver Driver (
        .CLK(SYSTEM_CLOCK),
        .RST,
        .EnableCount(1'b1),
        .RedPixels,
        .GrnPixels,
        .GPIO_1
    );

    // =========================================================================
    // Core Game Status (declared early for gating)
    // =========================================================================
    logic        winner_enable;   // Terminal flag (win or draw)
    logic [1:0]  winner_player;   // Winner identity (00 = draw)
    logic [1:0]  current_player;  // Active player (01 = P1, 10 = P2)

    // =========================================================================
    // Input Synchronization, Debounce, and Edge Detection
    // =========================================================================
    logic [3:0] key_s1, key_s2, key_clean, key_prev_clean;
    logic [9:0] sw_s1, sw_s2, sw_sync;
    logic [19:0] debounce_cnt[3:0];

    // Synchronize inputs to CLOCK_50
    always_ff @(posedge CLOCK_50) begin
        key_s1 <= KEY;
        key_s2 <= key_s1;
        sw_s1  <= SW;
        sw_s2  <= sw_s1;
    end
    assign sw_sync = sw_s2;

    // Debounce pushbuttons
    always_ff @(posedge CLOCK_50 or posedge RST) begin
        if (RST) begin
            key_clean <= 4'b1111;
            for (int i=0; i<4; i++) debounce_cnt[i] <= 0;
        end else begin
            for (int i=0; i<4; i++) begin
                if (key_s2[i] != key_clean[i]) begin
                    debounce_cnt[i] <= debounce_cnt[i] + 1;
                    if (debounce_cnt[i] == 20'd500000) begin
                        key_clean[i]    <= key_s2[i];
                        debounce_cnt[i] <= 0;
                    end
                end else debounce_cnt[i] <= 0;
            end
        end
    end

    // Track previous debounced state
    always_ff @(posedge CLOCK_50 or posedge RST) begin
        if (RST) key_prev_clean <= 4'b1111;
        else     key_prev_clean <= key_clean;
    end

    // Edge detection
    logic drop_edge_raw, drop_edge;
    assign drop_edge_raw = (key_prev_clean[0] & ~key_clean[0]); // KEY0 falling edge
    assign drop_edge     = drop_edge_raw && !winner_enable;     // Block input after terminal

    logic left_edge, right_edge;
    assign left_edge  = (key_prev_clean[2] & ~key_clean[2]); // KEY3
    assign right_edge = (key_prev_clean[3] & ~key_clean[3]); // KEY2

    logic reset_edge;
    assign reset_edge = sw_sync[9]; // Reset from slide switch

    // =========================================================================
    // Cursor Logic (Human-controlled column index)
    // =========================================================================
    logic [2:0] cursor_col_human;
    always_ff @(posedge CLOCK_50 or posedge RST) begin
        if (RST) cursor_col_human <= 3'd0;
        else begin
            if (left_edge  && cursor_col_human > 0) cursor_col_human <= cursor_col_human - 1;
            if (right_edge && cursor_col_human < 7) cursor_col_human <= cursor_col_human + 1;
        end
    end

    // =========================================================================
    // Core Game Wires
    // =========================================================================
    logic        column_full, win_found, board_full;
    logic        clear_board, drop_token, update_display, drop_requested;
    logic        switch_player_enable, validate_enable, find_row_enable;
    logic [1:0]  board[6][8];
    logic        drop_latched;

    // =========================================================================
    // Datapath
    // =========================================================================
    connect_four_datapath datapath (
        .clk(CLOCK_50),
        .reset(RST),
        .clear_board(clear_board),
        .validate_enable(validate_enable),
        .find_row_enable(find_row_enable),
        .drop_token(drop_token),
        .switch_player_enable(switch_player_enable),
        .cursor_col(cursor_col_human),
        .column_full(column_full),
        .win_found(win_found),
        .board_full(board_full),
        .board(board),
        .current_player(current_player)
    );

    // =========================================================================
    // Controller
    // =========================================================================
    connect_four_controller controller (
        .clk(CLOCK_50),
        .reset_edge(reset_edge | RST),
        .drop_edge(drop_edge),
        .game_enable(game_enable),
        .column_full(column_full),
        .win_found(win_found),
        .board_full(board_full),
        .current_player(current_player),
        .clear_board(clear_board),
        .drop_token(drop_token),
        .update_display(update_display),
        .drop_requested(drop_requested),
        .switch_player_enable(switch_player_enable),
        .validate_enable(validate_enable),
        .find_row_enable(find_row_enable),
        .winner_enable(winner_enable),
        .drop_latched(drop_latched),
        .winner_player(winner_player)
    );

    // =========================================================================
    // Display (LED Matrix)
    // =========================================================================
    logic game_over_enable;
    assign game_over_enable = winner_enable && (winner_player == 2'b00); // Draw flag

    connect_four_display display (
        .update_display(update_display),
        .winner_enable(winner_enable),
        .game_over_enable(game_over_enable),
        .board(board),
        .current_player(current_player),
        .cursor_col(cursor_col_human),
        .blink(blink),
        .RedPixels(RedPixels),
        .GrnPixels(GrnPixels)
    );

    // =========================================================================
    // HEX Display Logic (Winner Marquee / Draw)
    // =========================================================================
    logic [2:0] marquee_pos;
    logic       game_enable_prev;

    // Marquee position advances on game_enable rising while winner_enable is asserted
    always_ff @(posedge CLOCK_50 or posedge RST) begin
        if (RST) begin
            marquee_pos      <= 3'd0;
            game_enable_prev <= 1'b0;
        end else if (winner_enable) begin
            if (!game_enable_prev && game_enable)
                marquee_pos <= marquee_pos + 1;
            game_enable_prev <= game_enable;
        end else begin
            marquee_pos      <= 3'd0;
            game_enable_prev <= game_enable;
        end
    end

    // Active HEX digit for marquee animation
    logic [2:0] active_hex;
    always_comb begin
        case (marquee_pos)
            3'd0: active_hex = 3'd0;
            3'd1: active_hex = 3'd1;
            3'd2: active_hex = 3'd2;
            3'd3: active_hex = 3'd3;
            3'd4: active_hex = 3'd2;
            3'd5: active_hex = 3'd1;
            default: active_hex = 3'd0;
        endcase
    end

    // Drive HEX displays
    always_comb begin
        // Default: all digits off
        HEX0 = 7'b1111111;
        HEX1 = 7'b1111111;
        HEX2 = 7'b1111111;
        HEX3 = 7'b1111111;
        HEX4 = 7'b1111111;
        HEX5 = 7'b1111111;

        // Show current player while the game is running
        if (!winner_enable) begin
            case (current_player)
                2'b01: HEX0 = 7'b1111001; // "1"
                2'b10: HEX0 = 7'b0100100; // "2"
                default: HEX0 = 7'b1111111;
            endcase
        end

        // Winner marquee or draw
        if (winner_enable) begin
            case (winner_player)
                2'b01: begin
                    HEX5 = 7'b1111001; // "1"
                    case (active_hex)
                        3'd0: HEX4 = 7'b1111001;
                        3'd1: HEX3 = 7'b1111001;
                        3'd2: HEX2 = 7'b1111001;
                        3'd3: HEX1 = 7'b1111001;
                    endcase
                end
                2'b10: begin
                    HEX5 = 7'b0100100; // "2"
                    case (active_hex)
                        3'd0: HEX4 = 7'b0100100;
                        3'd1: HEX3 = 7'b0100100;
                        3'd2: HEX2 = 7'b0100100;
                        3'd3: HEX1 = 7'b0100100;
                    endcase
                end
                2'b00: begin
                    HEX5 = 7'b1000000; // "0" for draw
                end
            endcase
        end
    end
endmodule
// -----------------------------------------------------------------------------
// Connect Four — Top-Level Testbench
// -----------------------------------------------------------------------------
// Purpose:
// - Instantiate DE1_SoC top level and drive inputs.
// - Apply a scripted sequence of moves to produce a four-in-a-row win.
// - Allow ModelSim users to expand hierarchy and view controller/datapath/display.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module DE1_SoC_testbench();

    // -------------------------------------------------------------------------
    // DUT I/O
    // -------------------------------------------------------------------------
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    logic [9:0] LEDR;
    logic [3:0] KEY;
    logic [9:0] SW;
    logic [35:0] GPIO_1;
    logic CLOCK_50;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    DE1_SoC dut (
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
        .LEDR(LEDR),
        .KEY(KEY),
        .SW(SW),
        .GPIO_1(GPIO_1),
        .CLOCK_50(CLOCK_50)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (50 MHz)
    // -------------------------------------------------------------------------
    initial begin
        CLOCK_50 = 0;
        forever #10 CLOCK_50 = ~CLOCK_50; // 20 ns period = 50 MHz
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Initialize inputs
        KEY = 4'b1111; // all keys released
        SW  = 10'b0;   // all switches off

        // Apply reset
        SW[9] = 1;     // assert reset
        #100;
        SW[9] = 0;     // deassert reset

        // ---------------------------------------------------------------------
        // Scripted moves: Player 1 wins with four in a row in column 0
        // KEY0 = drop, KEY2 = right, KEY3 = left
        // Each press held for 10 ms to pass debounce
        // ---------------------------------------------------------------------

        // Player 1: drop in column 0
        press_key0();
        #200;

        // Player 2: move cursor right to column 1, drop
        press_key2(); press_key0();
        #200;

        // Player 1: drop again in column 0
        press_key3(); press_key0();
        #200;

        // Player 2: move cursor right to column 1, drop
        press_key2(); press_key0();
        #200;

        // Player 1: drop again in column 0
        press_key3(); press_key0();
        #200;

        // Player 2: move cursor right to column 1, drop
        press_key2(); press_key0();
        #200;

        // Player 1: final drop in column 0 (four in a row vertically)
        press_key3(); press_key0();
        #500;

        $display("Simulation finished: Player 1 should have four in a row, winner_enable asserted.");
        $stop;
    end

    // -------------------------------------------------------------------------
    // Helper tasks for key presses (respect debounce)
    // -------------------------------------------------------------------------
    task press_key0(); // drop
        begin
            KEY[0] = 0;
            #20_000_000; // hold for 10 ms
            KEY[0] = 1;
            #20_000_000; // release stable for 10 ms
        end
    endtask

    task press_key2(); // cursor right
        begin
            KEY[2] = 0;
            #20_000_000;
            KEY[2] = 1;
            #20_000_000;
        end
    endtask

    task press_key3(); // cursor left
        begin
            KEY[3] = 0;
            #20_000_000;
            KEY[3] = 1;
            #20_000_000;
        end
    endtask

endmodule

