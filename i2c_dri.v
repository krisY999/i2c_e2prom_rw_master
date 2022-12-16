module i2c_dri
    #(
      parameter   SLAVE_ADDR = 7'b1010000   ,  //EEPROM从机地址
      parameter   CLK_FREQ   = 26'd50_000_000, //模块输入的时钟频率
      parameter   I2C_FREQ   = 18'd250_000     //IIC_SCL的时钟频率 250K
    )
   (                                                            
    input                clk        ,    
    input                rst_n      ,   
                                         
    //i2c interface                      
    input                i2c_exec   ,  //I2C触发执行信号
    input                bit_ctrl   ,  //字地址位控制(16b/8b)
    input                i2c_rh_wl  ,  //I2C读写控制信号
    input        [15:0]  i2c_addr   ,  //I2C器件内地址
    input        [ 7:0]  i2c_data_w ,  //I2C要写的数据
    output  reg  [ 7:0]  i2c_data_r ,  //I2C读出的数据
    output  reg          i2c_done   ,  //I2C一次操作完成
    output  reg          i2c_ack    ,  //I2C应答标志 0:应答 1:未应答
    output  reg          scl        ,  //I2C的SCL时钟信号
    inout                sda        ,  //I2C的SDA信号
                                       
    //user interface                   
    output  reg          dri_clk       //驱动I2C操作的驱动时钟
     );
	 
	 
	 
	//localparam define
	localparam  st_idle     = 8'b0000_0001; //空闲状态
	localparam  st_sladdr   = 8'b0000_0010; //发送写！器件地址(slave address)
	localparam  st_addr16   = 8'b0000_0100; //发送16位字地址
	localparam  st_addr8    = 8'b0000_1000; //发送8位字地址
	localparam  st_data_wr  = 8'b0001_0000; //写数据(8 bit)
	localparam  st_addr_rd  = 8'b0010_0000; //发送器件地址读
	localparam  st_data_rd  = 8'b0100_0000; //读数据(8 bit)
	localparam  st_stop     = 8'b1000_0000; //结束I2C操作

    //reg define
	reg       		sda_dir ;
	reg				sda_out ;
    reg            	st_done   ; //状态结束
	reg             wr_flag   ;
	reg    [ 6:0]  	cnt       ; //计数
	reg    [ 7:0]  	cur_state ; //状态机当前状态
	reg    [ 7:0]  	next_state; //状态机下一状态
    reg    [15:0]  	addr_t    ; //地址
	reg    [ 7:0]  	data_r    ; //读取的数据
	reg    [ 7:0]  	data_wr_t ; //I2C需写的数据的临时寄存
    reg    [ 9:0]  	clk_cnt   ; //分频时钟计数
	
	//wire define
    wire 			sda_in  ;
    wire   [8:0]  clk_divide ; //模块驱动时钟的分频系数



	//SDA IO control
	assign  	sda 	= sda_dir?sda_out:1'bz;
	assign		sda_in  = sda	;
	assign      clk_divide = (CLK_FREQ/I2C_FREQ)>>2'd2 ; 


	//生成I2C的SCL的四倍频率的驱动时钟用于驱动i2c的操作：经典偶数次分频电路
	always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
		 dri_clk <= 1'b0;
		 clk_cnt <= 10'd0;
	end
	else if(clk_cnt == clk_divide[8:1] - 1'b1)begin
	     clk_cnt <= 10'd0;
		 dri_clk <= ~dri_clk;
	end
	else begin
	     clk_cnt <= clk_cnt + 1'b1;
		 dri_clk <= dri_clk;
	end
  end


	//FSM ****************************************************************************

	always @(posedge dri_clk or negedge rst_n) begin
    if(!rst_n) begin
		  cur_state <= st_idle ;
	end
	else begin
		  cur_state <= next_state ;
	end
  end

    //状态机转移逻辑
    always @ (*) begin
      next_state =  st_idle ; 
      case(cur_state)
		  st_idle ： begin   
			if(i2c_exec)           
				next_state = st_sladdr ;
			else 
				next_state = st_idle   ; 
		  end
		  
		  st_sladdr:  begin
			 if(st_done)begin
			    if(bit_ctrl)  
		           next_state = st_addr16 ;
				else 
				   next_state = st_addr8 ;
			 end 
			 else
			       next_state = st_sladdr ;
		  end
	      
		  st_addr16:  begin
			 if(st_done)begin 
		           next_state = st_addr8 ;
			 end 
			 else
			       next_state = st_addr16 ;
		  end

		  st_addr8:  begin
			 if(st_done)begin
			    if(wr_flag)  
		           next_state = st_addr_rd ;
				else 
				   next_state = st_data_wr ;
			 end 
			 else
			       next_state = st_addr8 ;
		  end

          st_data_wr:  begin
			 if(st_done)begin
				   next_state = st_stop 	;
			 end 
			 else
			       next_state = st_data_wr 	;
		  end

          st_addr_rd:  begin
			 if(st_done)begin
				   next_state = st_data_rd 	;
			 end 
			 else
			       next_state = st_addr_rd 	;
		  end
          
		   st_data_rd:  begin
			 if(st_done)begin
				   next_state = st_stop 	;
			 end 
			 else
			       next_state = st_data_rd 	;
		  end

            st_stop:  begin
			 if(st_done)begin
				   next_state = st_idle 	;
			 end 
			 else
			       next_state = st_stop 	;
		  end

			 default: next_state= st_idle;
	 endcase
   end



    //状态输出逻辑
    always @(posedge dri_clk or negedge rst_n) begin
    if(!rst_n) begin
		 scl       	<= 1'b1;  
		 sda_dir	<= 1'b1;  
		 sda_out	<= 1'b1;  
		 st_done	<= 1'b0;  
		 i2c_data_r <= 8'd0;
		 i2c_done   <= 1'd0;
		 i2c_ack    <= 1'd0;
		 wr_flag    <= 1'b0;
		 cnt        <= 1'b0;   
		 data_r    	<= 1'b0; 
		 data_wr_t 	<= 8'b0 ; //I2C需写的数据的临时寄存	
		 addr_t		<=	16'd0; 
	end
	else begin
	     st_done <= 1'b0 ;                            
         cnt     <= cnt +1'b1 ;     
	     case(cur_state)
	          st_idle: begin  
	              scl     <= 1'b1;                     
                  sda_out <= 1'b1;                     
                  sda_dir <= 1'b1;                     
                  i2c_done<= 1'b0;                     
                  cnt     <= 7'b0;       
				 if(i2c_exec)begin
	                wr_flag   <= i2c_rh_wl ;         
                    addr_t    <= i2c_addr  ;         
                    data_wr_t <= i2c_data_w;  
                    i2c_ack <= 1'b0;      
				end
			 end
	
	          st_sladdr: begin
	              case(cnt)
	               7'd1:  sda_out <= 1'b0;     //I2C start
	               7'd3:  scl     <= 1'b0;
				   7'd4:  sda_out 	  <= SLAVE_ADDR[6];
				   7'd5:  scl     <= 1'b1;
				   7'd7:  scl     <= 1'b0;
				   7'd8:  sda_out     <= SLAVE_ADDR[5];
				   7'd9:  scl     <= 1'b1;
				   7'd11: scl     <= 1'b0;
				   7'd12: sda_out     <= SLAVE_ADDR[4];
				   7'd13: scl     <= 1'b1;
				   7'd15: scl     <= 1'b0;
				   7'd16: sda_out     <= SLAVE_ADDR[3];
				   7'd17: scl     <= 1'b1;
				   7'd19: scl     <= 1'b0;
				   7'd20: sda_out     <= SLAVE_ADDR[2];
				   7'd21: scl     <= 1'b1;
				   7'd23: scl     <= 1'b0;
				   7'd24: sda_out     <= SLAVE_ADDR[1];
				   7'd25: scl     <= 1'b1;
				   7'd27: scl     <= 1'b0;
				   7'd28: sda_out     <= SLAVE_ADDR[0];
				   7'd29: scl     <= 1'b1;
				   7'd31: scl     <= 1'b0;
				   7'd32: sda_out     <= 1'b0;     //写命令0
				   7'd33: scl     <= 1'b1;
				   7'd35: scl     <= 1'b0;
				   7'd36: sda_dir <= 1'b0;  
				   7'd37: scl     <= 1'b1;
				   7'd38: begin                     //从机应答 
                        st_done <= 1'b1;
                        if(sda_in == 1'b1)           //高电平表示未应答
                            i2c_ack <= 1'b1;         //拉高应答标志位     
                    end                                          
				   7'd39: begin
				        cnt 	<= 0;
						scl     <= 1'b0;
				   end
				   default :  ;   
	              endcase
			end
	
			st_addr16: begin
	              case(cnt)
	               7'd0:  begin                     
                        sda_dir <= 1'b1 ;            
                        sda_out <= addr_t[15];       //传送字地址
                    end                                   
	               7'd1:  scl     <= 1'b1;
				   7'd3:  scl     <= 1'b0;
				   7'd4:  sda_out <= addr_t[14];  
				   7'd5:  scl     <= 1'b1;
				   7'd7:  scl     <= 1'b0;
				   7'd8:  sda_out <= addr_t[13]; 
				   7'd9:  scl     <= 1'b1;
				   7'd11:  scl     <= 1'b0;
				   7'd12:  sda_out <= addr_t[12]; 
				   7'd13:  scl     <= 1'b1;
				   7'd15:  scl     <= 1'b0;
				   7'd16:  sda_out <= addr_t[11]; 
				   7'd17:  scl     <= 1'b1;
				   7'd19:  scl     <= 1'b0;
				   7'd20:  sda_out <= addr_t[10]; 
				   7'd21:  scl     <= 1'b1;
				   7'd23:  scl     <= 1'b0;
				   7'd24:  sda_out <= addr_t[9]; 
				   7'd25:  scl     <= 1'b1;
				   7'd27:  scl     <= 1'b0;
				   7'd28:  sda_out <= addr_t[8]; 
				   7'd29:  scl     <= 1'b1;
				   7'd31:  scl     <= 1'b0;
				   7'd32: sda_dir  <= 1'b0; 
				   7'd33: scl      <= 1'b1;
				   7'd34: begin                     //从机应答 
                        st_done <= 1'b1;
                        if(sda_in == 1'b1)           //高电平表示未应答
                            i2c_ack <= 1'b1;         //拉高应答标志位     
                    end                                                            
				   7'd35: begin
				        cnt 	<= 0;
						scl     <= 1'b0;
				   end
				   default :  ;   
	              endcase
			end
	
	        st_addr8: begin
	              case(cnt)
	               7'd0:  begin                     
                        sda_dir <= 1'b1 ;            
                        sda_out <= addr_t[7];       //传送字地址
                    end                                   
	               7'd1:  scl     <= 1'b1;
				   7'd3:  scl     <= 1'b0;
				   7'd4:  sda_out <= addr_t[6];  
				   7'd5:  scl     <= 1'b1;
				   7'd7:  scl     <= 1'b0;
				   7'd8:  sda_out <= addr_t[5]; 
				   7'd9:  scl     <= 1'b1;
				   7'd11:  scl     <= 1'b0;
				   7'd12:  sda_out <= addr_t[4]; 
				   7'd13:  scl     <= 1'b1;
				   7'd15:  scl     <= 1'b0;
				   7'd16:  sda_out <= addr_t[3]; 
				   7'd17:  scl     <= 1'b1;
				   7'd19:  scl     <= 1'b0;
				   7'd20:  sda_out <= addr_t[2]; 
				   7'd21:  scl     <= 1'b1;
				   7'd23:  scl     <= 1'b0;
				   7'd24:  sda_out <= addr_t[1]; 
				   7'd25:  scl     <= 1'b1;
				   7'd27:  scl     <= 1'b0;
				   7'd28:  sda_out <= addr_t[0]; 
				   7'd29:  scl     <= 1'b1;
				   7'd31:  scl     <= 1'b0;
				   7'd32: sda_dir  <= 1'b0; 
				   7'd33: scl      <= 1'b1;
				   7'd34: begin                     //从机应答 
                        st_done <= 1'b1;
                        if(sda_in == 1'b1)           //高电平表示未应答
                            i2c_ack <= 1'b1;         //拉高应答标志位     
                    end                                                            
				   7'd35: begin
				        cnt 	<= 0;
						scl     <= 1'b0;
				   end
				   default :  ;   
	              endcase
			end
	
	        st_data_wr: begin                        //写数据(8 bit)
                case(cnt)                            
                    7'd0: begin                      
                        sda_out <= data_wr_t[7];     //I2C写8位数据
                        sda_dir <= 1'b1;             
                    end                              
                    7'd1 : scl <= 1'b1;              
                    7'd3 : scl <= 1'b0;              
                    7'd4 : sda_out <= data_wr_t[6];  
                    7'd5 : scl <= 1'b1;              
                    7'd7 : scl <= 1'b0;              
                    7'd8 : sda_out <= data_wr_t[5];  
                    7'd9 : scl <= 1'b1;              
                    7'd11: scl <= 1'b0;              
                    7'd12: sda_out <= data_wr_t[4];  
                    7'd13: scl <= 1'b1;              
                    7'd15: scl <= 1'b0;              
                    7'd16: sda_out <= data_wr_t[3];  
                    7'd17: scl <= 1'b1;              
                    7'd19: scl <= 1'b0;              
                    7'd20: sda_out <= data_wr_t[2];  
                    7'd21: scl <= 1'b1;              
                    7'd23: scl <= 1'b0;              
                    7'd24: sda_out <= data_wr_t[1];  
                    7'd25: scl <= 1'b1;              
                    7'd27: scl <= 1'b0;              
                    7'd28: sda_out <= data_wr_t[0];  
                    7'd29: scl <= 1'b1;              
                    7'd31: scl <= 1'b0;              
                    7'd32: begin                     
                        sda_dir <= 1'b0;           
                        sda_out <= 1'b1;                              
                    end                              
                    7'd33: scl <= 1'b1;              
                    7'd34: begin                     //从机应答
                        st_done <= 1'b1;     
                        if(sda_in == 1'b1)           //高电平表示未应答
                            i2c_ack <= 1'b1;         //拉高应答标志位    
                    end          
                    7'd35: begin                     
                        scl  <= 1'b0;                
                        cnt  <= 1'b0;                
                    end                              
                    default  :  ;                    
                endcase                              
            end                                      
	        
			//写地址以进行读数据
	        st_addr_rd: begin
	              case(cnt)
	                7'd0:  begin                     
                        sda_dir <= 1'b1 ;            
                        sda_out <= 1'b1;       
                    end          
	                7'd1:  scl     <= 1'b1;
				    7'd2:  sda_out <= 1'b0;       //IIC restart
				    7'd3:  scl     <= 1'b0;  
				    7'd4 : sda_out <= SLAVE_ADDR[6]; //传送器件地址
				    7'd5:  scl     <= 1'b1;
				    7'd7 : scl <= 1'b0;              
					7'd8 : sda_out <= SLAVE_ADDR[5]; 
					7'd9 : scl <= 1'b1;              
					7'd11: scl <= 1'b0;              
					7'd12: sda_out <= SLAVE_ADDR[4]; 
					7'd13: scl <= 1'b1;              
					7'd15: scl <= 1'b0;              
					7'd16: sda_out <= SLAVE_ADDR[3]; 
					7'd17: scl <= 1'b1;              
					7'd19: scl <= 1'b0;              
					7'd20: sda_out <= SLAVE_ADDR[2]; 
					7'd21: scl <= 1'b1;              
					7'd23: scl <= 1'b0;              
					7'd24: sda_out <= SLAVE_ADDR[1]; 
					7'd25: scl <= 1'b1;              
					7'd27: scl <= 1'b0;              
					7'd28: sda_out <= SLAVE_ADDR[0]; 
					7'd29: scl <= 1'b1;              
					7'd31: scl <= 1'b0;              
				    7'd32: sda_out <= 1'b1;          //1:read
				    7'd33: scl <= 1'b1;              
                    7'd35: scl <= 1'b0;              
                    7'd36: begin                     
                        sda_dir <= 1'b0;             
                        sda_out <= 1'b1;                //sda_dir拉低之后，此信号高低无影响          
                    end                              
                    7'd37: scl     <= 1'b1;            
                    7'd38: begin                     //从机应答 
                        st_done <= 1'b1;
                        if(sda_in == 1'b1)           //高电平表示未应答
                            i2c_ack <= 1'b1;         //拉高应答标志位     
                    end                                          
                    7'd39: begin                     
                        scl <= 1'b0;                 
                        cnt <= 1'b0;                 
                    end                              
                    default :  ;                     
                endcase                              
            end                                      
				   
				   
			 st_data_rd: begin                        //读取数据(8 bit)
                case(cnt)	   
		            7'd0: sda_dir <= 1'b0;   //切换至输入模式
					7'd1: begin
                        data_r[7] <= sda_in;
                        scl       <= 1'b1;
                    end
					7'd3: scl  <= 1'b0;
					7'd5: begin
                        data_r[6] <= sda_in ;
                        scl       <= 1'b1   ;
                    end
                    7'd7: scl  <= 1'b0;
                    7'd9: begin
                        data_r[5] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd11: scl  <= 1'b0;
                    7'd13: begin
                        data_r[4] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd15: scl  <= 1'b0;
                    7'd17: begin
                        data_r[3] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd19: scl  <= 1'b0;
                    7'd21: begin
                        data_r[2] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd23: scl  <= 1'b0;
                    7'd25: begin
                        data_r[1] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd27: scl  <= 1'b0;
                    7'd29: begin
                        data_r[0] <= sda_in;
                        scl       <= 1'b1  ;
                    end
					7'd31: scl  <= 1'b0;
					7'd32: begin
                        sda_dir <= 1'b1;             
                        sda_out <= 1'b1;
                    end
					7'd33: scl     <= 1'b1;
                    7'd34: st_done <= 1'b1;          //非应答
					7'd35: begin
                        scl <= 1'b0;
                        cnt <= 1'b0;
                        i2c_data_r <= data_r;
                    end
				default :  ;                     
                endcase                              
            end                   
	
	
	        st_stop: begin
			case(cnt)
			 7'd0: begin
                        sda_dir <= 1'b1;            
                        sda_out <= 1'b0;
            end
			7'd1 : 		scl     <= 1'b1;
			7'd3 : 		sda_out <= 1'b1; //结束I2C
			7'd15: 		st_done <= 1'b1;    //这里可做几个时钟周期的延迟，可变，不一定15
			7'd16: 		begin i2c_done <= 1'b1;
	                            cnt <= 1'b0;   end 
			default :  ;                     
            endcase                              
           end             
	  endcase	  
	end
  end 


endmodule




