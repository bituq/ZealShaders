/*
BSD 3-Clause License

Copyright (c) 2022, Dylan N (Zeal)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// My github: https://github.com/bituq

// Thanks to Ehsan2077 for inspiring me to make this shader.

#include "ReShade.fxh"
#include "Blending.fxh"

namespace AdaptiveRim
{

	uniform float3 Color <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's tint";
		ui_type = "color";
	> = float3(1, 1, 1);
	
	uniform float Strength <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's strength";
		ui_type = "slider";
		ui_min = 0; ui_max = 3; ui_step = .1;
	> = 2;
	
	uniform float Offset <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's offset";
		ui_type = "slider";
		ui_min = 0.1; ui_max = 10; ui_step = .1;
	> = 2.5;
	
	uniform float Detail <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's details";
		ui_type = "slider";
		ui_min = 0; ui_max = 1; ui_step = .01;
	> = .4;
	
	uniform float DepthInfluence <
		ui_label = "Depth Influence";
		ui_category = "Rim";
		ui_tooltip = "Increasing this value will make the rim thinner further away";
		ui_type = "slider";
		ui_min = 0; ui_max = 1; ui_step = .1;
	> = 0.3;
	
	uniform float RimBlurSize <
		ui_label = "Blur Amount";
		ui_category = "Rim";
		ui_type = "slider";
		ui_min = 1; ui_max = 10; ui_step = .1;
	> = 3.6;
	
	uniform bool Adaptive <
		ui_category = "Environment";
		ui_tooltip = "Make the backlight adaptive to lighting in its environment";
	> = true;
	
	uniform uint ColorBlurSize <
		ui_label = "Light Distance";
		ui_type = "slider";
		ui_category = "Environment";
		ui_min = 1; ui_max = 100;
	> = 80;
	
	uniform float Brightness <
		ui_type = "slider";
		ui_category = "Environment";
		ui_min = 1; ui_max = 20; ui_step = .1;
	> = 2;
	
	uniform float Saturation <
		ui_type = "slider";
		ui_category = "Environment";
		ui_min = 0;
		ui_max = 1; ui_step = .01; 
	> = .5;
	
	uniform float Threshold <
		ui_category = "Environment";
		ui_type = "slider";
		ui_min = 0; ui_max = 1; ui_step = .01;
	> = .2;
	
	uniform uint Blend <
		ui_type = "combo";
		ui_label = "Blending Mode";
		ui_items = "Color Dodge\0Overlay\0";
		ui_tooltip = "Adjust the blending mode of the rim light. DEFAULT = Color Dodge";
		ui_category = "Image";
	> = 0;
	
	uniform uint Debug <
		ui_type = "combo";
		ui_label = "Mode";
		ui_items = "Off\0Rim\0Final Rim\0Blur\0Normals\0Luma\0";
		ui_tooltip = "Adjust the debug mode. DEFAULT = Off";
		ui_category = "Debug Tools";
		ui_category_closed = true;
	> = 0;
	
	uniform bool DepthMapReversed <
		ui_label = "Reverse Depth Map";
		ui_tooltip = "Enable if the depth map is reversed.";
		ui_category = "Debug Tools";
	> = false;
	
	uniform bool DepthMapFlip <
		ui_label = "Flip Depth Map";
		ui_tooltip = "Enable if the depth map is flipped upside down.";
		ui_category = "Debug Tools";
	> = false;
	
	texture TexNormals { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
	sampler sTexNormals { Texture = TexNormals; };
	
	texture TexLuma { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; MipLevels = 11; };
	sampler sTexLuma {Texture = TexLuma; SRGBTexture = true; };	
	
	texture TexHColorBlur { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; };
	sampler sTexHColorBlur {Texture = TexHColorBlur;};
	
	texture TexColorBlur { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; MipLevels = 4; };
	sampler sTexColorBlur { Texture = TexColorBlur;};
	
	texture TexRim { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT;};
	sampler sTexRim {Texture = TexRim;};	
	
	texture TexHRimBlur { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
	sampler sTexHRimBlur {Texture = TexHRimBlur;};
	
	float GetDepth(in float2 tc)
	{
		float depth;
		if (!DepthMapFlip)
			tc.y = 1.0 - tc.y;
	
		depth = tex2Dlod(ReShade::DepthBuffer, float4(tc, 0, 0)).x;
	
		if (DepthMapReversed)
			depth = 1 - depth;
		
		return depth;
	}
	
	float3 NormalVector(in float4 pos : SV_Position, in float2 tc: TexCoord) : SV_Target
	{
		float Depth = ReShade::GetLinearizedDepth(tc);
			
		// Rim becomes thinner farther away
		float3 offset = pow(abs(1 - Depth), lerp(1, 8, DepthInfluence).x);
		offset *= Offset / 1000; // Set to 100 for LSD shader ;)
		offset += float3(BUFFER_PIXEL_SIZE.xy, 0);
		
		const float2 posCenter = tc.xy;
		const float2 posNorth = posCenter - offset.zy;
		const float2 posEast = posCenter + offset.xz;
	
		const float3 vertCenter = float3(posCenter - .5, 1) * GetDepth(posCenter);
		const float3 vertNorth = float3(posNorth - 0.5, 1) * GetDepth(posNorth);
		const float3 vertEast = float3(posEast - 0.5, 1) * GetDepth(posEast);
	
		return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast)) * 0.5;
	}
	
	int MapBlendingMode(int ComboOption)
	{
		if (ComboOption == 0) // Color Dodge
			return 7;
		else if (ComboOption == 1) // Overlay
			return 8;
		else
			return 1; // Normal
	}
	
	// Luma pass
	void Luma(in float4 pos : SV_Position, in float2 tc : TexCoord, out float4 color : SV_Target)
	{
		color = tex2D(ReShade::BackBuffer, tc).rgb;
		
		// Isolate bright luma
		float intensity = dot(color.rgb, float3(.2126, .7152, .0722));
		color.rgb /= max(intensity, 0.0001);
		color.a = pow(10, ReShade::GetLinearizedDepth(tc));
		color.a *= max(0, intensity - Threshold);
		color.rgb *= color.a;
		
		color = float4(color.rgb, intensity);
	}
	
	// Backlight pixel shader
	float3 Rimlight(in float4 pos : SV_Position, in float2 tc : TexCoord): SV_Target
	{
		float3 color = cross(tex2D(sTexNormals, tc).rgb, float3(0, lerp(1, 0, Detail), 1));
		return color.r * Color ;
	}
	
	// Horizontal blur
	float3 HBlur(in float4 pos : SV_Position, in float2 tc : TexCoord, in sampler tex, in float bs, in float steps)
	{
		float3 color;
		for (int i = -bs; i <= bs; i++)
			color += (bs - abs(i))*tex2D( tex, tc + float2(( BUFFER_RCP_WIDTH * ( ( steps * i ) + 0.5)), 0)).rgb;	
		return color/((bs*bs));
	}
	
	// Vertical blur
	float3 VBlur(in float4 pos : SV_Position, in float2 tc : TexCoord, in sampler tex, in float bs, in float steps)
	{
		float3 color;
		for (int i = -bs; i <= bs; i++)
			color += (bs - abs(i))*tex2D( tex, tc + float2(0,( BUFFER_RCP_HEIGHT * ( ( steps * i ) + 0.5 )))).rgb;
		return color/(bs*bs);
	}
	
	// Horizontal rim blur pass
	float3 HRimBlur(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		return HBlur(pos, tc, sTexRim, RimBlurSize, 2);
	}
	
	// Horizontal color blur pass
	float3 HColorBlur(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		float3 large = HBlur(pos, tc, sTexLuma, max(1, ColorBlurSize), 10);
		float3 small = HBlur(pos, tc, sTexLuma, max(1, ColorBlurSize / 8), 8);
		return small + large;
	}
	
	// Final color blur pass
	float3 ColorBlur(float4 pos : SV_Position, float2 tc: TexCoord) : SV_Target
	{
		float3 large = VBlur(pos, tc, sTexHColorBlur, max(1, ColorBlurSize / 4), 8);
		float3 small = VBlur(pos, tc, sTexLuma, max(1, ColorBlurSize / 8), 8);
		float3 color = small + large;
		
		float grayscale = dot(color, .333);
		color = saturate(lerp(grayscale, color, lerp(0, 2, Saturation)));
		
		return saturate(color * Brightness);
	}
	
	float3 Result(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		float3 RimBlur = VBlur(pos, tc, sTexHRimBlur, RimBlurSize, 2);
		float3 backBuffer = tex2D(ReShade::BackBuffer, tc).rgb;
		float3 color = backBuffer;
		
		if (Adaptive)
			color = tex2Dlod(sTexColorBlur, float4(tc, 0, 4)).rgb;
		
		float3 result = saturate(ComHeaders::Blending::Blend(1, color, RimBlur, 1));
		float brightness = tex2Dlod(sTexLuma, float4(tc, 0, 5)).a;
		brightness = smoothstep(1, -1, brightness);
		brightness *= Strength;
		result *= Strength;;
		
		
		if (Debug == 1)
			result = tex2D(sTexRim, tc).rgb;
		else if (Debug == 2)
			return result;
		else if (Debug == 3)
			result = tex2Dlod(sTexColorBlur, float4(tc, 0, 5)).rgb;
		else if (Debug == 4)
			result = tex2D(sTexNormals, tc).rgb;
		else if (Debug == 5)
			result = brightness;
		else
			result = ComHeaders::Blending::Blend(MapBlendingMode(Blend), tex2D(ReShade::BackBuffer, tc).rgb, result, 1);
		
		return result;
	}
	
	technique RimLight < ui_label = "Adaptive Rimlight"; ui_tooltip = "Adaptive rim lighting // By Zeal //"; >
	{
		pass Normals
		{
			VertexShader = PostProcessVS;
			PixelShader = NormalVector;
			RenderTarget = TexNormals;
		}
		pass Luma
		{
			VertexShader = PostProcessVS;
			PixelShader = Luma;
			RenderTarget = TexLuma;
		}
		pass HColorBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = HColorBlur;
			RenderTarget = TexHColorBlur;
		}
		pass ColorBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = ColorBlur;
			RenderTarget = TexColorBlur;
		}
		pass Rim
		{
			VertexShader = PostProcessVS;
			PixelShader = Rimlight;
			RenderTarget = TexRim;
		}
		pass HRimBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = HRimBlur;
			RenderTarget = TexHRimBlur;
		}
		pass Result
		{
			VertexShader = PostProcessVS;
			PixelShader = Result;
		}
	}
}