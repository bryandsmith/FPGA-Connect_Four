// -----------------------------------------------------------------------------
// Connect Four AI (Level 1 Random; robust handshake; explicit EMPTY encoding)
// -----------------------------------------------------------------------------
module connect_four_ai (
    input  logic        clk,
    input  logic        reset,
    input  logic        ai_start,          // high while controller is in INPUT_AI
    input  logic [1:0]  board[6][8],       // board state (for legality check)

    output logic [2:0]  ai_col,            // chosen column
    output logic        ai_done            // asserted until controller leaves INPUT_AI
);

    // Adjust EMPTY if your datapath uses a different encoding
    localparam logic [1:0] EMPTY = 2'b00;

    // 10-bit LFSR for pseudo-random sequence
    logic [9:0] lfsr_out;

    LFSR lfsr_inst (
        .clk   (clk),
        .reset (reset),
        .Qin   (10'b1010101010), // fixed non-zero seed
        .Qout  (lfsr_out)
    );

    typedef enum logic [1:0] {IDLE, THINK, DONE} ai_state_t;
    ai_state_t ps, ns;

    logic [2:0] ai_col_reg;
    logic       ai_done_reg;

    assign ai_col  = ai_col_reg;
    assign ai_done = ai_done_reg;

    // State register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) ps <= IDLE;
        else       ps <= ns;
    end

    // Next-state logic
    always_comb begin
        ns = ps;
        unique case (ps)
            IDLE:  if (ai_start) ns = THINK;
            THINK: ns = DONE;                     // choose column then go DONE
            DONE:  if (!ai_start) ns = IDLE;      // controller left INPUT_AI
        endcase
    end

    // Decision + handshake
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ai_col_reg  <= 3'd0;
            ai_done_reg <= 1'b0;
        end else begin
            case (ps)
                IDLE: begin
                    ai_done_reg <= 1'b0;
                end

                THINK: begin
                    int tries;
                    int c;
                    int found;
						  found = 0;

                    // Scan starting from LFSR offset for a non-full column
                    for (tries = 0; tries < 8; tries++) begin
                        c = (lfsr_out + tries) % 8;
                        if (board[0][c] == EMPTY) begin
                            ai_col_reg <= c[2:0];
                            found = 1;
                            break;
                        end
                    end

                    // If none found (board likely full), still set a column so controller can proceed
                    if (!found) begin
                        ai_col_reg <= lfsr_out[2:0]; // arbitrary column; controller will handle draw
                    end

                    ai_done_reg <= 1'b0; // not done yet
                end

                DONE: begin
                    // Hold ai_done high while controller is in INPUT_AI
                    ai_done_reg <= ai_start;
                    // Keep ai_col_reg latched; datapath samples via cursor mux
                end
            endcase
        end
    end

endmodule

// -----------------------------------------------------------------------------
// 10-bit LFSR
// -----------------------------------------------------------------------------
module LFSR (
    input  logic clk,
    input  logic reset,
    input  logic [9:0] Qin,
    output logic [9:0] Qout
);
    logic [9:0] lfsr;
    logic feedback;

    assign Qout = lfsr;
    assign feedback = ~(lfsr[9] ^ lfsr[6]); // XNOR taps

    always_ff @(posedge clk) begin
        if (reset)
            lfsr <= Qin;
        else
            lfsr <= {feedback, lfsr[9:1]};
    end
endmodule