/*
 * Copyright (c) 2016 AMD Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and/or associated documentation files (the
 * "Materials"), to deal in the Materials without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Materials, and to
 * permit persons to whom the Materials are furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * MATERIALS OR THE USE OR OTHER DEALINGS IN THE MATERIALS.
 */

#define _FLOAT					float
#define _FLOAT2					float2
#define _FLOAT4					float4
#define _FLOAT8					float8

#ifndef FLT_MAX
#define FLT_MAX         3.402823466e+38F        /* max value */
#endif

#define MLO_POOLING_OP_AVE			0
#define MLO_POOLING_OP_MAX			1
#define MLO_POOLING_OP_STC			2


#define MLO_POOLBWD_GROUP_SZ2 1


#define MLO_POOLBWD_LCL_DATA_WIDTH (MLO_POOLBWD_GROUP_SZ0 *MLO_POOLBWD_N_VERT_OUT_PIX + MLO_POOLING_KERNEL_SZ0 + MLO_POOLING_STRIDE0 - 1) / MLO_POOLING_STRIDE0
#define MLO_POOLBWD_LCL_DATA_HEIGHT (MLO_POOLBWD_GROUP_SZ1 *MLO_POOLBWD_N_VERT_OUT_PIX  + MLO_POOLING_KERNEL_SZ1 + MLO_POOLING_STRIDE1 - 1) / MLO_POOLING_STRIDE1


__attribute__((reqd_work_group_size(MLO_POOLBWD_GROUP_SZ0,MLO_POOLBWD_GROUP_SZ1,MLO_POOLBWD_GROUP_SZ2)))
__kernel void mloPoolingAveBwd(
       const __global _FLOAT * top_diff,
        __global _FLOAT * bot_diff
	   )
{
		__local _FLOAT lcl_top_diff[MLO_POOLBWD_LCL_DATA_WIDTH * MLO_POOLBWD_LCL_DATA_HEIGHT];

		int x = get_group_id(0) * MLO_POOLBWD_GROUP_SZ0 * MLO_POOLBWD_N_HORIZ_OUT_PIX;
		int y = get_group_id(1) * MLO_POOLBWD_GROUP_SZ1 * MLO_POOLBWD_N_VERT_OUT_PIX;
		int lcl_id0 = get_local_id(0);
		int lcl_id1 = get_local_id(1);
//		int lcl_id = (lcl_id1 << MLO_POOLBWD_GROUP_LG2SZ1) + lcl_id0;
		int ob = get_global_id(2); // outputs * batch_sz
		int b = (int)(float)ob / (float)MLO_POOLING_N_OUTPUTS;
		int o = ob - b * MLO_POOLING_N_OUTPUTS;


		int top_x = (x + MLO_POOLING_PAD0 - MLO_POOLING_KERNEL_SZ0) < 0 ? 0 : (x + MLO_POOLING_PAD0 - MLO_POOLING_KERNEL_SZ0)/ MLO_POOLING_STRIDE0 + 1;
		int top_y = (y + MLO_POOLING_PAD1 - MLO_POOLING_KERNEL_SZ1) < 0 ? 0 : (y + MLO_POOLING_PAD1 - MLO_POOLING_KERNEL_SZ1) / MLO_POOLING_STRIDE1 + 1;
		int top_off = b * MLO_POOLBWD_TOP_BATCH_STRIDE + o * MLO_POOLBWD_TOP_CHANNEL_STRIDE;


		_FLOAT res[MLO_POOLBWD_N_VERT_OUT_PIX][MLO_POOLBWD_N_HORIZ_OUT_PIX];
		for( int k = 0; k < MLO_POOLBWD_N_VERT_OUT_PIX; k++)
		{
			for(int l = 0; l < MLO_POOLBWD_N_HORIZ_OUT_PIX; l++)
			{
				res[k][l] = 0;
			}
		}


// load tile
		for( int tj = lcl_id1; tj < MLO_POOLBWD_LCL_DATA_HEIGHT; tj += MLO_POOLBWD_GROUP_SZ1)
		{	
			int top_y_act = top_y + tj;
			int top_y_off = top_y_act * MLO_POOLBWD_TOP_STRIDE;

			int lcl_off_v = tj * MLO_POOLBWD_LCL_DATA_WIDTH;

			bool invisibleY = (top_y_act >= MLO_POOLBWD_TOP_HEIGHT);

			for(int ti = lcl_id0; ti < MLO_POOLBWD_LCL_DATA_WIDTH; ti += MLO_POOLBWD_GROUP_SZ0)
			{

				int top_x_act = top_x + ti;
				
				bool invisibleX = (top_x_act >= MLO_POOLBWD_TOP_WIDTH);

				_FLOAT top_val = top_diff[top_off + top_y_off + top_x_act];


				top_val = (invisibleX || invisibleY)? 0 : top_val;
								
				lcl_top_diff[lcl_off_v + ti] = top_val;
#if 0
				if (lcl_id1==0&&o==0&&b==0)
				{
				  printf("K:in: %d %d %d   %f\n", top_off + top_y_off + top_x_act, top_y_act, top_x_act, top_val);
				}
#endif
				
			}
		}

		barrier(CLK_LOCAL_MEM_FENCE);

		int bot_y = (y + lcl_id1 * MLO_POOLBWD_N_VERT_OUT_PIX);
		int bot_x = (x + lcl_id0 * MLO_POOLBWD_N_HORIZ_OUT_PIX);


		for( int k = 0; k < MLO_POOLBWD_N_VERT_OUT_PIX; k++)
		{

			int h = bot_y + k + MLO_POOLING_PAD1;
			int top_hstart = (h < MLO_POOLING_KERNEL_SZ1) ? 0 : (h - MLO_POOLING_KERNEL_SZ1) / MLO_POOLING_STRIDE1 + 1;
			int top_hend = min(h / MLO_POOLING_STRIDE1 + 1, MLO_POOLBWD_TOP_HEIGHT);

			for(int l = 0; l < MLO_POOLBWD_N_HORIZ_OUT_PIX; l++)
			{


				int	w = bot_x + l + MLO_POOLING_PAD0;
				int top_wstart = (w < MLO_POOLING_KERNEL_SZ0) ? 0 : (w - MLO_POOLING_KERNEL_SZ0) / MLO_POOLING_STRIDE0 + 1;
				int top_wend = min(w / MLO_POOLING_STRIDE0 + 1, MLO_POOLBWD_TOP_WIDTH);
		

				for (int top_h = top_hstart; top_h < top_hend; ++top_h)
				{
				    int hstart = top_h * MLO_POOLING_STRIDE1 - MLO_POOLING_PAD1;
					int hend = min(hstart + MLO_POOLING_KERNEL_SZ1, MLO_POOLBWD_BOT_HEIGHT + MLO_POOLING_PAD1);

					for (int top_w =top_wstart; top_w < top_wend; ++top_w)
					{
        // figure out the pooling size
						int wstart = top_w * MLO_POOLING_STRIDE0 - MLO_POOLING_PAD0;
						int wend = min(wstart + MLO_POOLING_KERNEL_SZ0, MLO_POOLBWD_BOT_WIDTH + MLO_POOLING_PAD0);
						int pool_size = (hend - hstart) * (wend - wstart);
						int lcl_top_h = top_h - top_y;
						int lcl_top_w = top_w - top_x;
						_FLOAT add_val = (lcl_top_diff[lcl_top_h *  MLO_POOLBWD_LCL_DATA_WIDTH + lcl_top_w] / (_FLOAT)pool_size);
						res[k][l] += add_val;
#if 0
				if (bot_x+l==6&&bot_y+k==0&&o==3&&b==0)
				{
				  printf("K:com: %d %d %d %d %d %d   %10.8f %10.8f %10.8f %d\n", k,l,top_h, top_w, lcl_top_h, lcl_top_w, res[k][l], add_val, lcl_top_diff[lcl_top_h *  MLO_POOLBWD_LCL_DATA_WIDTH + lcl_top_w], pool_size);
				}
#endif
					}
				}


			}
		}

		int bot_off = b * MLO_POOLBWD_BOT_BATCH_STRIDE + o * MLO_POOLBWD_BOT_CHANNEL_STRIDE + bot_y * MLO_POOLBWD_BOT_STRIDE + bot_x;
		for( int k = 0; k < MLO_POOLBWD_N_VERT_OUT_PIX; k++)
		{
			for(int l = 0; l < MLO_POOLBWD_N_HORIZ_OUT_PIX; l++)
			{
				if (bot_y + k < MLO_POOLBWD_BOT_HEIGHT && bot_x + l < MLO_POOLBWD_BOT_WIDTH)
				{	
					bot_diff[bot_off + k * MLO_POOLBWD_BOT_STRIDE +l] = res[k][l];
#if 0
					if (lcl_id0==0&&lcl_id1==0&&o==0&&b==0)
					{
						printf("K:out: %d %d %d  %f\n", bot_off + k * MLO_POOLBWD_BOT_STRIDE +l, k, l, bot_diff[bot_off + k * MLO_POOLBWD_BOT_STRIDE +l]);
					}
#endif

				}
			}
		}

}


#define MLO_LCL_BOT_WIDTH (MLO_POOLBWD_GROUP_SZ0 *MLO_POOLBWD_N_VERT_OUT_PIX + MLO_POOLING_KERNEL_SZ0)
#define MLO_LCL_BOT_HEIGHT (MLO_POOLBWD_GROUP_SZ1 *MLO_POOLBWD_N_VERT_OUT_PIX  + MLO_POOLING_KERNEL_SZ1)

__attribute__((reqd_work_group_size(MLO_POOLBWD_GROUP_SZ0,MLO_POOLBWD_GROUP_SZ1,MLO_POOLBWD_GROUP_SZ2)))
__kernel void mloPoolingMaxBwd(
       const __global _FLOAT * top_df,
       __global _FLOAT * bot_df,
       const __global _FLOAT * top,
       const __global _FLOAT * bot
	   )
{
		__local _FLOAT lcl_top_df[MLO_POOLBWD_LCL_DATA_WIDTH * MLO_POOLBWD_LCL_DATA_HEIGHT];
		__local _FLOAT lcl_top[MLO_POOLBWD_LCL_DATA_WIDTH * MLO_POOLBWD_LCL_DATA_HEIGHT];
		__local _FLOAT lcl_bot[MLO_LCL_BOT_WIDTH * MLO_LCL_BOT_HEIGHT];

		int x = get_group_id(0) * MLO_POOLBWD_GROUP_SZ0 * MLO_POOLBWD_N_HORIZ_OUT_PIX;
		int y = get_group_id(1) * MLO_POOLBWD_GROUP_SZ1 * MLO_POOLBWD_N_VERT_OUT_PIX;
		int lcl_id0 = get_local_id(0);
		int lcl_id1 = get_local_id(1);
		int ob = get_global_id(2); // outputs * batch_sz
		int b = (int)(float)ob / (float)MLO_POOLING_N_OUTPUTS;
		int o = ob - b * MLO_POOLING_N_OUTPUTS;


		int top_x = (x + MLO_POOLING_PAD0 - MLO_POOLING_KERNEL_SZ0) < 0 ? 0 : (x + MLO_POOLING_PAD0 - MLO_POOLING_KERNEL_SZ0)/ MLO_POOLING_STRIDE0 + 1;
		int top_y = (y + MLO_POOLING_PAD1 - MLO_POOLING_KERNEL_SZ1) < 0 ? 0 : (y + MLO_POOLING_PAD1 - MLO_POOLING_KERNEL_SZ1) / MLO_POOLING_STRIDE1 + 1;
		int top_df_off = b * MLO_POOLBWD_TOPDF_BATCH_STRIDE + o * MLO_POOLBWD_TOPDF_CHANNEL_STRIDE;
		int top_off = b * MLO_POOLBWD_TOP_BATCH_STRIDE + o * MLO_POOLBWD_TOP_CHANNEL_STRIDE;
		int bot_off = b * MLO_POOLBWD_BOT_BATCH_STRIDE + o * MLO_POOLBWD_BOT_CHANNEL_STRIDE;
		int bot_x = x;
		int bot_y = y;

		_FLOAT res[MLO_POOLBWD_N_VERT_OUT_PIX][MLO_POOLBWD_N_HORIZ_OUT_PIX];



// load tiles
// top df and top
		for( int tj = lcl_id1; tj < MLO_POOLBWD_LCL_DATA_HEIGHT; tj += MLO_POOLBWD_GROUP_SZ1)
		{	
			int top_y_act = top_y + tj;
			int top_df_y_off = top_y_act * MLO_POOLBWD_TOPDF_STRIDE;
			int top_y_off = top_y_act * MLO_POOLBWD_TOP_STRIDE;

			int lcl_off_v = tj * MLO_POOLBWD_LCL_DATA_WIDTH;

			bool invisibleY = (top_y_act >= MLO_POOLBWD_TOP_HEIGHT);

			for(int ti = lcl_id0; ti < MLO_POOLBWD_LCL_DATA_WIDTH; ti += MLO_POOLBWD_GROUP_SZ0)
			{

				int top_x_act = top_x + ti;
				
				bool invisibleX = (top_x_act >= MLO_POOLBWD_TOP_WIDTH);

				_FLOAT top_df_val = top_df[top_df_off + top_df_y_off + top_x_act];
				top_df_val = (invisibleX || invisibleY)? 0 : top_df_val;
				_FLOAT top_val = top[top_off + top_y_off + top_x_act];
				top_val = (invisibleX || invisibleY)? 0 : top_val;

								
				lcl_top_df[lcl_off_v + ti] = top_df_val;
				lcl_top[lcl_off_v + ti] = top_val;
				
			}
		}

		for( int tj = lcl_id1; tj < MLO_LCL_BOT_HEIGHT; tj += MLO_POOLBWD_GROUP_SZ1)
		{	
			int bot_y_act = bot_y + tj;
			int bot_y_off = bot_y_act * MLO_POOLBWD_BOT_STRIDE;

			int lcl_off_v = tj * MLO_LCL_BOT_WIDTH;

			bool invisibleY = (bot_y_act >= MLO_POOLBWD_BOT_HEIGHT);

			for(int ti = lcl_id0; ti < MLO_LCL_BOT_WIDTH; ti += MLO_POOLBWD_GROUP_SZ0)
			{

				int bot_x_act = bot_x + ti;
				
				bool invisibleX = (bot_x_act >= MLO_POOLBWD_BOT_WIDTH);

				_FLOAT bot_val = bot[bot_off + bot_y_off + bot_x_act];
				bot_val = (invisibleX || invisibleY)? 0 : bot_val;

								
				lcl_bot[lcl_off_v + ti] = bot_val;
				
			}
		}

		barrier(CLK_LOCAL_MEM_FENCE);

		int bt_y = (y + lcl_id1 * MLO_POOLBWD_N_VERT_OUT_PIX);
		int bt_x = (x + lcl_id0 * MLO_POOLBWD_N_HORIZ_OUT_PIX);

		int lcl_bt_y = (lcl_id1 * MLO_POOLBWD_N_VERT_OUT_PIX);
		int lcl_bt_x = (lcl_id0 * MLO_POOLBWD_N_HORIZ_OUT_PIX);


		for( int k = 0; k < MLO_POOLBWD_N_VERT_OUT_PIX; k++)
		{

			int b_y = bt_y + k;
// top most top y that can be influenced by this bot y

			int tt_y = (b_y + MLO_POOLING_PAD1 -  MLO_POOLING_KERNEL_SZ1 + MLO_POOLING_STRIDE1)  / MLO_POOLING_STRIDE1;
			tt_y = (tt_y < 0 ) ? 0 : tt_y;

			for(int l = 0; l < MLO_POOLBWD_N_HORIZ_OUT_PIX; l++)
			{
				int	b_x = bt_x + l;
// left most top x that can be influenced by this bot x
				int lt_x = (b_x + MLO_POOLING_PAD0 -  MLO_POOLING_KERNEL_SZ0 + MLO_POOLING_STRIDE0)  / MLO_POOLING_STRIDE0;
				lt_x = (lt_x < 0 ) ? 0 : lt_x;
				
// find and sum up all tops that have been influenced by particular bot
				res[k][l] = 0;
				for (int th = tt_y; th < tt_y + (MLO_POOLING_KERNEL_SZ1 + MLO_POOLING_STRIDE1 - 1)  / MLO_POOLING_STRIDE1; ++th)
				{
					int src_y = th * MLO_POOLING_STRIDE1;
					bool invisY = (b_y + MLO_POOLING_PAD1 - src_y > MLO_POOLING_KERNEL_SZ1 - 1 || b_y + MLO_POOLING_PAD1 - src_y < 0);
					for (int tw = lt_x; tw < lt_x + (MLO_POOLING_KERNEL_SZ0 + MLO_POOLING_STRIDE0 - 1)  / MLO_POOLING_STRIDE0; ++tw)
					{
						int lcl_th = th - top_y;
						int lcl_tw = tw - top_x;

						int src_x = tw * MLO_POOLING_STRIDE0;
						bool invisX = (b_x + MLO_POOLING_PAD0 - src_x > MLO_POOLING_KERNEL_SZ0 - 1 || b_x + MLO_POOLING_PAD0 - src_x < 0);
						_FLOAT add_val = lcl_top_df[lcl_th *  MLO_POOLBWD_LCL_DATA_WIDTH + lcl_tw] 
						* (lcl_top[lcl_th *  MLO_POOLBWD_LCL_DATA_WIDTH + lcl_tw] == lcl_bot[(lcl_bt_y +k) * MLO_LCL_BOT_WIDTH + lcl_bt_x +l]);
						res[k][l] += ( invisY || invisX)? 0 : add_val;

#if 0
								if (b==0 && o == 0 && b_x == 9 && b_y == 0)
								{
									printf("K:max: %d %d %d %d %d %d   %13.11f  %13.11f  %13.11f  %13.11f %13.11f\n",
									    b_x + MLO_POOLING_PAD0,
										src_x,
										tw, th,
										k,l,
										res[k][l],
										add_val, 
										lcl_top_df[lcl_th *  MLO_POOLBWD_LCL_DATA_WIDTH + lcl_tw] ,
										lcl_top[lcl_th *  MLO_POOLBWD_LCL_DATA_WIDTH + lcl_tw],
										lcl_bot[(lcl_bt_y +k) * MLO_LCL_BOT_WIDTH + lcl_bt_x +l]
										);
								}
#endif
					}
				}


			}
		}

		int bot_df_off = b * MLO_POOLBWD_BOTDF_BATCH_STRIDE + o * MLO_POOLBWD_BOTDF_CHANNEL_STRIDE + bt_y * MLO_POOLBWD_BOTDF_STRIDE + bt_x;
		for( int k = 0; k < MLO_POOLBWD_N_VERT_OUT_PIX; k++)
		{
			for(int l = 0; l < MLO_POOLBWD_N_HORIZ_OUT_PIX; l++)
			{
				if ((bt_y + k) < MLO_POOLBWD_BOT_HEIGHT && (bt_x + l) < MLO_POOLBWD_BOT_WIDTH)
				{	
					bot_df[bot_df_off + k * MLO_POOLBWD_BOTDF_STRIDE +l] = res[k][l];
#if 0
								if (b==0 && o ==0 && bt_x +l == 9 && bt_y + k== 0)
								{
									printf("K:max: %d %d   %13.11f\n",
										k, l,
										res[k][l]
										);
								}
#endif
				}
			}
		}

}
