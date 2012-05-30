/********************************************/
/* ctrl_regs.v                              */
/* control registers                        */
/*                                          */
/* 2012, rok.krajnc@gmail.com               */
/********************************************/



module ctrl_regs #(
  parameter QAW = 22,             // qmem address width
  parameter QDW = 32,             // qmem data width
  parameter QSW = QDW/8           // qmem select width
)(
  // system
  input  wire           clk,
  input  wire           rst,
  // qmem bus
  input  wire [QAW-1:0] adr,
  input  wire           cs,
  input  wire           we,
  input  wire [QSW-1:0] sel,
  input  wire [QDW-1:0] dat_w,
  output reg  [QDW-1:0] dat_r,
  output reg            ack,
  output wire           err,
  // registers
  output reg            sys_rst,
  output reg            minimig_rst,
  output wire           uart_txd
);


localparam RAW = 6; // address width for register decoding

initial sys_rst = 1'b0; // initial value for sys_rst



////////////////////////////////////////
// address register                   //
////////////////////////////////////////

reg  [RAW-1:0] adr_r;

always @ (posedge clk, posedge rst) begin
  if (rst)
    adr_r <= #1 {RAW{1'b0}};
  else
    adr_r <= #1 adr[RAW-1:0];
end



////////////////////////////////////////
// UART transmit                      //
////////////////////////////////////////

// TODO maye add TX buffer - fifo?

// TX counter
reg  [  4-1:0] tx_counter;
reg  [  9-1:0] tx_timer;
wire           tx_ready;
reg            tx_en;

always @ (posedge clk, posedge rst) begin
  if (rst)
    tx_counter <= #1 4'd0;
  else if (tx_en && tx_ready)
    tx_counter <= #1 4'd10 - 4'd1;
  else if ((|tx_counter) && (~|tx_timer))
    tx_counter <= #1 tx_counter - 4'd1;
end

// TX timer

always @ (posedge clk, posedge rst) begin
  if (rst)
    tx_timer <= #1 9'd434 - 9'd1;
  else if (tx_en && tx_ready)
    tx_timer <= #1 9'd434 - 9'd1;
  else if (|tx_timer)
    tx_timer <= #1 tx_timer - 9'd1;
  else if (|tx_counter)
    tx_timer <= #1 9'd434 - 9'd1;
end

// TX register
reg  [ 10-1:0] tx_reg;

always @ (posedge clk, posedge rst) begin
  if (rst)
    tx_reg <= #1 10'b1111111111;
  else if (tx_en && tx_ready)
    tx_reg <= #1 {1'b1, dat_w[7:0], 1'b0};
  else if (~|tx_timer)
    tx_reg <= #1 {1'b1, tx_reg[9:1]};
end

// TX ready
assign tx_ready = (~|tx_counter) && (~|tx_timer);

// UART TXD
assign uart_txd = tx_reg[0];



////////////////////////////////////////
// timer                              //
////////////////////////////////////////

reg  [ 16-1:0] timer;
reg  [ 16-1:0] pre_timer;
reg            timer_en;

// pre counter
always @ (posedge clk, posedge rst) begin
  if (rst)
    pre_timer <= #1 16'd50_000 - 16'd1;
  else if (timer_en)
    pre_timer <= #1 16'd50_000 - 16'd1;
  else if (~|pre_timer)
    pre_timer <= #1 16'd50_000 - 16'd1;
  else 
    pre_timer <= #1 pre_timer - 16'd1;
end

// counter
// using pre_timer, this increases each milisecond
always @ (posedge clk, posedge rst) begin
  if (rst)
    timer <= #1 16'h0000;
  else if (timer_en)
    timer <= #1 dat_w[15:0];
  else if (~|pre_timer)
    timer <= #1 timer + 16'h1;
end



////////////////////////////////////////
// register enable                    //
////////////////////////////////////////

always @ (*) begin
  if (cs && we) begin
    case(adr[5:2])
      3'h2    : tx_en     = 1'b1;
      3'h3    : timer_en  = 1'b1;
      default : begin
        tx_en     = 1'b0;
        timer_en  = 1'b0;
      end
    endcase
  end else begin
    tx_en     = 1'b0;
    timer_en  = 1'b0;
  end
end



////////////////////////////////////////
// register write                     //
////////////////////////////////////////

always @ (posedge clk, posedge rst) begin
  if (rst) begin
    sys_rst       <= #1 1'b0;
    minimig_rst   <= #1 1'b1;
  end else if (cs && we) begin
    case(adr[5:2])
      3'h0  : sys_rst       <= #1 dat_w[    0];
      3'h1  : minimig_rst   <= #1 dat_w[    0];
    endcase
  end
end



////////////////////////////////////////
// register read                      //
////////////////////////////////////////

always @ (*) begin
  case(adr_r[5:2])
    3'h3    : dat_r = {16'h0000, timer}; 
    default : dat_r = 32'hxxxxxxxx;
  endcase
end



////////////////////////////////////////
// ack & err                          //
////////////////////////////////////////

// ack
always @ (*) begin
  case(adr[5:2])
    3'h2    : ack = cs && tx_ready;
    default : ack = cs;
  endcase
end

// err
assign err = 1'b0;



endmodule

