// -----------------------------------------------------------------------------
// Connect Four — Datapath
// -----------------------------------------------------------------------------
// Responsibilities:
// - Maintain board state (8 columns × 6 rows).
// - Track current player and last move coordinates.
// - Detect wins (registered after commit and fast-path during drop).
// - Detect draws (board full).
// - Provide feedback signals to controller (column full, win, board full).
// -----------------------------------------------------------------------------
module connect_four_datapath (
    // -------------------------------------------------------------------------
    // Inputs (control strobes from controller)
    // -------------------------------------------------------------------------
    input  logic clk,                   // system clock
    input  logic reset,                 // synchronous reset
    input  logic clear_board,           // reset board state
    input  logic validate_enable,       // check column fullness
    input  logic find_row_enable,       // resolve lowest empty row
    input  logic drop_token,            // commit token to board
    input  logic switch_player_enable,  // advance to next player
    input  logic [2:0] cursor_col,      // active cursor column

    // -------------------------------------------------------------------------
    // Outputs (feedback to controller)
    // -------------------------------------------------------------------------
    output logic column_full,           // true if cursor column is already full
    output logic win_found,             // OR of registered win and fast-path win
    output logic board_full,            // predictive full-board flag
    output logic [1:0] board[6][8],     // board state array
    output logic [1:0] current_player   // active player (1 or 2)
);

    // =========================================================================
    // Internal Registers and Latches
    // =========================================================================
    logic [2:0] target_row;             // resolved row for current drop
    logic [2:0] last_row, last_col;     // coordinates of last move
    logic [1:0] last_player;            // identity of last mover

    logic column_full_r;                // registered column-full flag
    logic win_status;                   // registered win flag (from last committed move)
    logic win_comb;                     // combinational win detection (last move)
    logic win_next;                     // fast-path win detection (pending move)
    logic board_full_next;              // predictive full-board detection

    // Temporary accumulators for win detection
    int horiz_total, vert_total, diag1_total, diag2_total;
    int horiz_next, vert_next, diag1_next, diag2_next;

    // =========================================================================
    // Sequential Updates (board state, player tracking, registered win)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (reset || clear_board) begin
            // Reset board and state
            column_full_r <= 1'b0;
            win_status    <= 1'b0;

            for (int r=0; r<6; r++) begin
                for (int c=0; c<8; c++) begin
                    board[r][c] <= 2'b00;
                end
            end

            current_player <= 2'b01;      // start with player 1
            last_row       <= 3'b111;     // invalid row marker
            last_col       <= 3'b000;
            last_player    <= 2'b00;      // no player yet

        end else begin
            // Column-full detection (top cell occupied)
            if (validate_enable)
                column_full_r <= (board[0][cursor_col] != 2'b00);

            // Switch player when controller pulses
            if (switch_player_enable)
                current_player <= (current_player == 2'b01) ? 2'b10 : 2'b01;

            // Capture target row/col when controller requests
            if (find_row_enable) begin
                last_row <= target_row;
                last_col <= cursor_col;
            end

            // Commit token to board on drop
            if (drop_token && (last_row != 3'b111)) begin
                last_player <= current_player;
                board[last_row][last_col] <= current_player;
            end

            // Registered win detection (based on last committed move)
            win_status <= win_comb;
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign column_full = column_full_r;
    assign win_found   = win_status || win_next; // OR registered + fast-path
    assign board_full  = board_full_next;        // predictive draw detection

    // =========================================================================
    // Lowest Empty Row Finder (combinational)
    // =========================================================================
    always_comb begin
        target_row = 3'b111; // invalid by default
        if (find_row_enable) begin
            for (int r = 5; r >= 0; r--) begin
                if (board[r][cursor_col] == 2'b00) begin
                    target_row = r[2:0];
                    break;
                end
            end
        end
    end

    // =========================================================================
    // Helper Function: Count contiguous pieces in a direction
    // =========================================================================
    function automatic int count_dir(
        input int row, col, drow, dcol,
        input logic [1:0] player
    );
        int cnt = 0;
        for (int step=1; step<=3; step++) begin
            int r = row + drow*step;
            int c = col + dcol*step;
            if (r >= 0 && r < 6 && c >= 0 && c < 8 && board[r][c] == player)
                cnt++;
            else
                break;
        end
        return cnt;
    endfunction

    // =========================================================================
    // Win Detection Around Last Committed Token (registered path)
    // =========================================================================
    always_comb begin
        win_comb     = 0;
        horiz_total  = 0;
        vert_total   = 0;
        diag1_total  = 0;
        diag2_total  = 0;

        if (last_player != 2'b00 && last_row != 3'b111) begin
            horiz_total = 1 + count_dir(last_row, last_col, 0, -1, last_player)
                            + count_dir(last_row, last_col, 0, +1, last_player);
            vert_total  = 1 + count_dir(last_row, last_col, -1, 0, last_player)
                            + count_dir(last_row, last_col, +1, 0, last_player);
            diag1_total = 1 + count_dir(last_row, last_col, -1, -1, last_player)
                            + count_dir(last_row, last_col, +1, +1, last_player);
            diag2_total = 1 + count_dir(last_row, last_col, +1, -1, last_player)
                            + count_dir(last_row, last_col, -1, +1, last_player);

            if (horiz_total >= 4 || vert_total >= 4 ||
                diag1_total >= 4 || diag2_total >= 4)
                win_comb = 1;
        end
    end

    // =========================================================================
    // Fast-Path Win Detection (pending move, same cycle as drop_token)
    // =========================================================================
    always_comb begin
        win_next   = 0;
        horiz_next = 0;
        vert_next  = 0;
        diag1_next = 0;
        diag2_next = 0;

        if (drop_token && last_row != 3'b111) begin
            horiz_next = 1 + count_dir(last_row, last_col, 0, -1, current_player)
                           + count_dir(last_row, last_col, 0, +1, current_player);
            vert_next  = 1 + count_dir(last_row, last_col, -1, 0, current_player)
                           + count_dir(last_row, last_col, +1, 0, current_player);
            diag1_next = 1 + count_dir(last_row, last_col, -1, -1, current_player)
                           + count_dir(last_row, last_col, +1, +1, current_player);
            diag2_next = 1 + count_dir(last_row, last_col, +1, -1, current_player)
                           + count_dir(last_row, last_col, -1, +1, current_player);

            if (horiz_next >= 4 || vert_next >= 4 ||
                diag1_next >= 4 || diag2_next >= 4)
                win_next = 1;
        end
    end

    // =========================================================================
    // Predictive Full-Board Detection (same cycle as pending drop)
    // =========================================================================
    // Treat the just-dropped token as occupying its cell; the board is full
    // when every top cell is (or will be) occupied after this drop.
    always_comb begin
        board_full_next = 1;
        for (int c=0; c<8; c++) begin
            if (!(board[0][c] != 2'b00 ||
                  (drop_token && c == last_col && last_row == 3'd0))) begin
                board_full_next = 0;
                break;
            end
        end
    end

endmodule