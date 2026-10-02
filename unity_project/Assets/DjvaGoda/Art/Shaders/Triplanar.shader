// Трипланарный материал мира ДжваГода (URP).
//
// Все сетки игры процедурные (рельеф, деревья, камни, постройки, люди), и
// UV-развёртки у них нет — текстура накладывается по трём осям и смешивается
// по нормали. Неподвижное — в мировых координатах (швов между соседними
// кусками нет); движущееся (_ObjectSpace = 1) — в координатах самого объекта,
// но в метрах (масштаб объекта учтён), иначе текстура «плыла» бы по
// идущему персонажу и растягивалась на вытянутых частях.
//
// Свет — главный источник с тенями и окружение (SH); туман. Текстура —
// оттенки серого или цветная, умножается на _BaseColor: так одна «ткань»
// красится в цвет любой стороны.
Shader "DjvaGoda/Triplanar"
{
    Properties
    {
        _BaseMap ("Текстура", 2D) = "white" {}
        _BaseColor ("Оттенок", Color) = (1, 1, 1, 1)
        _Scale ("Повторов на метр", Float) = 0.5
        _Sharpness ("Резкость смешения осей", Range(1, 16)) = 4
        _ObjectSpace ("В координатах объекта", Float) = 0
        _Smoothness ("Гладкость", Range(0, 1)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            float _Scale;
            float _Sharpness;
            float _ObjectSpace;
            half _Smoothness;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        // Точка и нормаль для наложения: мир или объект в метрах.
        void MappingSpace(float3 positionOS, float3 normalOS, float3 positionWS, float3 normalWS,
            out float3 p, out float3 n)
        {
            float3 scale = float3(
                length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20)),
                length(float3(UNITY_MATRIX_M._m01, UNITY_MATRIX_M._m11, UNITY_MATRIX_M._m21)),
                length(float3(UNITY_MATRIX_M._m02, UNITY_MATRIX_M._m12, UNITY_MATRIX_M._m22)));
            p = lerp(positionWS, positionOS * scale, _ObjectSpace);
            n = normalize(lerp(normalWS, normalOS, _ObjectSpace));
        }

        half4 Sample3(float3 p, float3 w, float s, float2 shift)
        {
            half4 x = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, p.zy * s + shift);
            half4 y = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, p.xz * s + shift);
            half4 z = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, p.xy * s + shift);
            return x * w.x + y * w.y + z * w.z;
        }

        half4 Triplanar(float3 p, float3 n)
        {
            float3 w = pow(abs(n), _Sharpness);
            w /= max(w.x + w.y + w.z, 1e-4);
            half4 detail = Sample3(p, w, _Scale, 0);
            // Крупная вариация: та же текстура в ~7 раз крупнее и со сдвигом
            // мягко меняет яркость — повтор плитки на поле перестаёт читаться сеткой.
            half4 macro = Sample3(p, w, _Scale * 0.137, float2(0.37, 0.71));
            half lum = dot(macro.rgb, half3(0.299, 0.587, 0.114));
            half avg = dot(SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, float2(0.5, 0.5), 16).rgb, half3(0.299, 0.587, 0.114));
            return detail * clamp(lum / max(avg, 0.05), 0.7, 1.3);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 mapP : TEXCOORD2;
                float3 mapN : TEXCOORD3;
                float fog : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                MappingSpace(input.positionOS.xyz, input.normalOS, pos.positionWS, nrm.normalWS, o.mapP, o.mapN);
                o.fog = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half4 albedo = Triplanar(i.mapP, i.mapN) * _BaseColor;
                float3 n = normalize(i.normalWS);
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light light = GetMainLight(shadowCoord);
                half ndl = saturate(dot(n, light.direction));
                half3 direct = light.color * ndl * light.shadowAttenuation * light.distanceAttenuation;
                half3 ambient = SampleSH(n);
                // Лёгкий блик: камень и металл не должны быть ватными.
                float3 v = normalize(GetWorldSpaceViewDir(i.positionWS));
                float3 h = normalize(light.direction + v);
                half spec = pow(saturate(dot(n, h)), lerp(8.0, 96.0, _Smoothness)) * _Smoothness * light.shadowAttenuation;
                half3 color = albedo.rgb * (direct + ambient) + light.color * spec * 0.5;
                color = MixFog(color, i.fog);
                return half4(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float4 Vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirection = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirection = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirection));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return positionCS;
            }

            half4 Frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float4 Vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                return TransformObjectToHClip(input.positionOS.xyz);
            }

            half4 Frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

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
            };

            Varyings Vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }

            half4 Frag(Varyings i) : SV_Target { return half4(normalize(i.normalWS), 0); }
            ENDHLSL
        }
    }
}
