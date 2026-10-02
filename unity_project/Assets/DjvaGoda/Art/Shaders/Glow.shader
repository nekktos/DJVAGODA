// Свечение (URP): огненный шар, вспышки заклинаний, угли горна. Без света и
// теней, прозрачное и складывающееся с фоном; ярче к середине и по краю
// (кайма), слегка дрожит — живой огонь, а не крашеный шар.
Shader "DjvaGoda/Glow"
{
    Properties
    {
        _BaseColor ("Цвет", Color) = (1, 0.5, 0.2, 1)
        _Intensity ("Яркость", Float) = 1.5
        _Rim ("Кайма", Range(0, 4)) = 1.5
        _Flicker ("Дрожь", Range(0, 1)) = 0.15
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }
        Blend SrcAlpha One
        ZWrite Off
        Cull Back

        Pass
        {
            Name "Glow"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _Intensity;
                float _Rim;
                float _Flicker;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float3 viewWS : TEXCOORD1;
                float3 positionOS : TEXCOORD2;
            };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionCS = pos.positionCS;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.viewWS = GetWorldSpaceViewDir(pos.positionWS);
                o.positionOS = input.positionOS.xyz;
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 v = normalize(i.viewWS);
                float facing = saturate(dot(n, v));
                float rim = pow(1.0 - facing, 2.0) * _Rim;
                float core = pow(facing, 3.0);
                float t = _Time.y;
                float flicker = 1.0 + (sin(t * 23.0 + i.positionOS.y * 9.0) * 0.5 + sin(t * 37.0 + i.positionOS.x * 13.0) * 0.5) * _Flicker;
                half3 color = _BaseColor.rgb * (core * 1.2 + rim) * _Intensity * flicker;
                half alpha = saturate((core * 0.8 + rim * 0.6) * _BaseColor.a);
                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
}
