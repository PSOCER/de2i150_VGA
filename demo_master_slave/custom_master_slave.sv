// custom_master_slave module : Acts as an avalon slave to receive input commands from PCIE IP

module custom_master_slave #(
	parameter MASTER_ADDRESSWIDTH = 26 ,  	// ADDRESSWIDTH specifies how many addresses the Master can address 
	parameter SLAVE_ADDRESSWIDTH = 3 ,  	// ADDRESSWIDTH specifies how many addresses the slave needs to be mapped to. log(NUMREGS)
	parameter DATAWIDTH = 32 ,    		// DATAWIDTH specifies the data width. Default 32 bits
	parameter NUMREGS = 8 ,       		// Number of Internal Registers for Custom Logic
	parameter REGWIDTH = 32       		// Data Width for the Internal Registers. Default 32 bits
)	
(	
	input logic  clk,
   input logic  reset_n,
	
	// Interface to Top Level
	input logic rdwr_cntl,					// Control Read or Write to a slave module.
	input logic n_action,					// Trigger the Read or Write. Additional control to avoid continuous transactions. Not a required signal. Can and should be removed for actual application.
	input logic add_data_sel,				// Interfaced to switch. Selects either Data or Address to be displayed on the Seven Segment Displays.
	input logic [MASTER_ADDRESSWIDTH-1:0] rdwr_address,	// read_address if required to be sent from another block. Can be unused if consecutive reads are required.
	output logic [DATAWIDTH-1:0] display_data,

	// Bus Slave Interface
        input logic [SLAVE_ADDRESSWIDTH-1:0] slave_address,
        input logic [DATAWIDTH-1:0] slave_writedata,
        input logic  slave_write,
        input logic  slave_read,
        input logic  slave_chipselect,
//      input logic  slave_readdatavalid, 			// These signals are for variable latency reads. 
//	output logic slave_waitrequest,   			// See the Avalon Specifications for details  on how to use them.
        output logic [DATAWIDTH-1:0] slave_readdata,

	// Bus Master Interface
        output logic [MASTER_ADDRESSWIDTH-1:0] master_address,
        output logic [DATAWIDTH-1:0] master_writedata,
        output logic  master_write,
        output logic  master_read,
        input logic [DATAWIDTH-1:0] master_readdata,
        input logic  master_readdatavalid,
        input logic  master_waitrequest
		  
);


parameter START_BYTE = 32'hF00BF00B;
parameter STOP_BYTE = 32'hDEADF00B;
parameter SDRAM_ADDR = 32'h08000000;

logic [MASTER_ADDRESSWIDTH-1:0] address, nextAddress;
logic [DATAWIDTH-1:0] nextRead_data, read_data;
logic [DATAWIDTH-1:0] nextData, wr_data;
logic [NUMREGS-1:0][REGWIDTH-1:0] csr_registers;  		// Command and Status Registers (CSR) for custom logic 
logic [NUMREGS-1:0] reg_index, nextRegIndex;
logic [NUMREGS-1:0][REGWIDTH-1:0] read_data_registers;  //Store SDRAM read data for display
logic new_data_flag;

typedef enum {IDLE, WRITE} state_t;
state_t state, nextState;

assign display_data = csr_registers[slave_address];

// Slave side 
always_ff @ ( posedge clk ) begin 
  if(!reset_n)
  	begin
    		slave_readdata <= 32'h0;
 	      	csr_registers <= '0;
  	end
  else 
  	begin
  	  if(slave_write && slave_chipselect && (slave_address >= 0) && (slave_address < NUMREGS))
  	  	begin
  	  	   csr_registers[slave_address] <= slave_writedata;  // Write a value to a CSR register
  	  	end
  	  else if(slave_read && slave_chipselect  && (slave_address >= 0) && (slave_address < NUMREGS)) // reading a CSR Register
  	    	begin
       		// Send a value being requested by a master. 
       		// If the computation is small you may compute directly and send it out to the master directly from here.
  	    	   slave_readdata <= csr_registers[slave_address];
  	    	end
  	 end
end

// Master Side
always_ff @ ( posedge clk ) begin 
	if (!reset_n) begin 
		address <= SDRAM_ADDR; //always start out at the base address of SDRAM, where pixel buffer is looking
		state <= WRITE; 
	end else begin 
		state <= nextState;
		address <= nextAddress;
	end
end

//Next State Logic 
always_comb begin 
	nextState = state;
	nextAddress = address;
	master_write = 1'b0;
	master_writedata = '0;
	master_address = address;
	case( state ) 
		WRITE: begin
			master_write = 1; //write enable must be set high to write to SDRAM
			master_address =  address; //address in SDRAM to write to (initialized to SDRAM's base address and same place that pixel buffer is looking at)
			master_writedata = 32'h00FF0000; //(Blue = 32'h00FF0000, Green = 32'h0000FF00, Red = 32'h000000FF)
			if (!master_waitrequest) begin //if not currently writing, go on to next address, otherwise wait for write to finish
				nextAddress = address + 4; // address is in hex, and each is 32 bits wide, so move up by 4 hex
				if(nextAddress == 32'h08CD2000) //if at the end of a 640x480 image space then go to idle (no need to write the entire SDRAM over)
				begin
					nextState = IDLE;
				end
				else //else keep on writing
				begin
					nextState = WRITE;
				end			
			end
		end 
		
		IDLE : 
		begin
			nextState = IDLE;
		end
		
	endcase
end

endmodule


