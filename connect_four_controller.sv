// -----------------------------------------------------------------------------
// Connect Four — Controller
// -----------------------------------------------------------------------------
// Responsibilities:
// - Implement the finite state machine (FSM) that sequences gameplay.
// - Respond to user input (drop requests) and datapath feedback (column full,
//   win, board full).
// - Generate control strobes for the datapath (validate, find row, drop token,
//   update display, switch player, clear board).
// - Track winner identity and lock the game once terminal.
// -----------------------------------------------------------------------------
module connect_four_controller (
    input  logic clk,             // system clock
    input  logic reset_edge,      // synchronous reset pulse
    input  logic drop_edge,       // one-cycle user drop request
    input  logic game_enable,     // pacing/enable (optional: unused for gating)

    // Feedback from datapath
    input  logic column_full,     // true if cursor column top cell occupied
    input  logic win_found,       // win flag from datapath
    input  logic board_full,      // full-board flag
    input  logic [1:0] current_player, // active player identity

    // Control strobes to datapath
    output logic clear_board,          // reset board state
    output logic drop_token,           // commit token to board
    output logic update_display,       // refresh LED matrix
    output logic drop_requested,       // signal that a drop was requested
    output logic switch_player_enable, // advance to next player
    output logic validate_enable,      // check column fullness
    output logic find_row_enable,      // resolve lowest empty row

    // Status outputs
    output logic winner_enable,        // terminal flag (win or draw)
    output logic drop_latched,         // latched drop request
    output logic [1:0] winner_player   // winner identity (00 = draw)
);

    // =========================================================================
    // FSM State Definitions
    // =========================================================================
    typedef enum logic [3:0] {
        INIT,           // clear board and initialize
        IDLE,           // waiting for input
        INPUT_PLAYER,   // accept human drop request
        VALIDATE,       // check if chosen column is full
        FIND_ROW,       // resolve lowest empty row
        DROP_TOKEN,     // commit token to board
        UPDATE_DISPLAY, // refresh LED matrix
        SWITCH_PLAYER,  // advance to next player
        WINNER          // terminal state (win or draw)
    } state_t;

    state_t ps, ns; // present state, next state

    // =========================================================================
    // Internal Qualifiers and Latches
    // =========================================================================
    logic game_locked; // once terminal, block further input

    // =========================================================================
    // State Register and Core Latches
    // =========================================================================
    always_ff @(posedge clk) begin
        if (reset_edge) begin
            ps            <= INIT;
            drop_latched  <= 1'b0;
            winner_player <= 2'b00;
            game_locked   <= 1'b0;
        end else begin
            ps <= ns;

            // Latch user drop request; clear when entering VALIDATE
            if (!game_locked && drop_edge)
                drop_latched <= 1'b1;
            else if (ps == VALIDATE)
                drop_latched <= 1'b0;

            // Winner identity: capture when win or draw detected
            if ((ps == DROP_TOKEN && win_found) ||
                (ps == UPDATE_DISPLAY && win_found)) begin
                winner_player <= current_player; // win
            end else if (ps == UPDATE_DISPLAY && board_full) begin
                winner_player <= 2'b00;          // draw
            end

            // Lock game once terminal
            if (ps == WINNER)
                game_locked <= 1'b1;
        end
    end

    // =========================================================================
    // Next-State Logic
    // =========================================================================
    always_comb begin
        ns = ps;
        unique case (ps)
            INIT:           ns = IDLE;
            IDLE:           ns = INPUT_PLAYER;
            INPUT_PLAYER:   ns = (!game_locked && drop_latched) ? VALIDATE : INPUT_PLAYER;
            VALIDATE:       ns = column_full ? INPUT_PLAYER : FIND_ROW;
            FIND_ROW:       ns = DROP_TOKEN;
            DROP_TOKEN:     ns = UPDATE_DISPLAY;
            UPDATE_DISPLAY: ns = (win_found || board_full) ? WINNER : SWITCH_PLAYER;
            SWITCH_PLAYER:  ns = IDLE;
            WINNER:         ns = reset_edge ? INIT : WINNER;
            default:        ns = INIT;
        endcase
    end

    // =========================================================================
    // Output Strobes
    // =========================================================================
    always_ff @(posedge clk) begin
        if (reset_edge) begin
            clear_board          <= 1'b0;
            drop_token           <= 1'b0;
            update_display       <= 1'b0;
            drop_requested       <= 1'b0;
            switch_player_enable <= 1'b0;
            validate_enable      <= 1'b0;
            find_row_enable      <= 1'b0;
            winner_enable        <= 1'b0;
        end else begin
            // Default all strobes low
            clear_board          <= 1'b0;
            drop_token           <= 1'b0;
            update_display       <= 1'b0;
            drop_requested       <= 1'b0;
            switch_player_enable <= 1'b0;
            validate_enable      <= 1'b0;
            find_row_enable      <= 1'b0;
            winner_enable        <= 1'b0;

            // Assert strobes based on current state
            unique case (ps)
                INIT: begin
                    clear_board    <= 1'b1;
                    update_display <= 1'b1;
                end

                INPUT_PLAYER: begin
                    if (!game_locked && drop_latched)
                        drop_requested <= 1'b1;
                end

                VALIDATE: begin
                    validate_enable <= 1'b1;
                end

                FIND_ROW: begin
                    find_row_enable <= 1'b1;
                end

                DROP_TOKEN: begin
                    drop_token <= 1'b1;
                    if (win_found)
                        winner_enable <= 1'b1;
                end

                UPDATE_DISPLAY: begin
                    update_display <= 1'b1;
                    if (win_found || board_full)
                        winner_enable <= 1'b1;
                end

                SWITCH_PLAYER: begin
                    switch_player_enable <= 1'b1;
                end

                WINNER: begin
                    winner_enable <= 1'b1;
                end
            endcase
        end
    end

endmodule