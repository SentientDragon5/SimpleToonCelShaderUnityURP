// SentientDragon5 1/21/22 

Shader "Toon/SimpleToon"
{
    // This is a more complicated toon shader in hlsl
    // Features: mainlight lighting, additional lights lighting, specular, rim lighting, alpha clip

    Properties
    {
        [HideInInspector]  _BaseMap("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _Cull("__cull", Float) = 2.0

        _ReceiveShadows("Receive Shadows", Float) = 1.0

        // Editmode props
        [HideInInspector] _QueueOffset("Queue offset", Float) = 0.0

        [MainTexture] _MainTex ("Base (RGB) Trans (A)", 2D) = "white" {}
        [HDR] _AmbientColor("Ambient Color", Color) = (0.8,0.8,0.8,1)
	    [HDR] _SpecularColor("Specular Color", Color) = (0.9,0.9,0.9,1)
	    _Glossiness("Glossiness", Float) = 32

        [HDR] _ShadowColor("ShadowColor", Color) = (0.4,0.4,0.4,1)
        [HDR] _RimColor("Rim Color", Color) = (1,1,1,1)
	    _RimAmount("Rim Amount", Range(0, 1)) = 0.716
    	_RimThreshold("Rim Threshold", Range(0, 1)) = 0.1
    }

    SubShader
    {
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline" "IgnoreProjector" = "True"}
        LOD 300
        Pass
        {
            Name "StandardLit"
            Tags{"LightMode" = "UniversalForward"}

            Blend[_SrcBlend][_DstBlend]
            ZWrite[_ZWrite]
            Cull[_Cull]

            HLSLPROGRAM
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICSPECGLOSSMAP
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _OCCLUSIONMAP

            #pragma shader_feature _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature _SPECULAR_SETUP
            #pragma shader_feature _RECEIVE_SHADOWS_OFF

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            #pragma multi_compile_instancing

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
                float2 uvLM         : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv                       : TEXCOORD0;
                float2 uvLM                     : TEXCOORD1;
                float4 positionWSAndFogFactor   : TEXCOORD2; 
                half3  normalWS                 : TEXCOORD3;

#if _NORMALMAP
                half3 tangentWS                 : TEXCOORD4;
                half3 bitangentWS               : TEXCOORD5;
#endif

#ifdef _MAIN_LIGHT_SHADOWS
                float4 shadowCoord              : TEXCOORD6;
#endif
                float4 positionCS               : SV_POSITION;
            };

            Varyings LitPassVertex(Attributes input)
            {
                Varyings output;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.uvLM = input.uvLM.xy * unity_LightmapST.xy + unity_LightmapST.zw;

                output.positionWSAndFogFactor = float4(vertexInput.positionWS, fogFactor);
                output.normalWS = vertexNormalInput.normalWS;

#ifdef _NORMALMAP
                output.tangentWS = vertexNormalInput.tangentWS;
                output.bitangentWS = vertexNormalInput.bitangentWS;
#endif

#ifdef _MAIN_LIGHT_SHADOWS
                output.shadowCoord = GetShadowCoord(vertexInput);
#endif
                output.positionCS = vertexInput.positionCS;
                return output;
            }

            
            sampler2D _MainTex;
            float4 _MainTex_ST;
            
            float4 _Color;
			float4 _AmbientColor;
			float4 _SpecularColor;
			float _Glossiness;		
			float4 _RimColor;
			float _RimAmount;
			float _RimThreshold;
            float4 _ShadowColor;

            half4 LitPassFragment(Varyings input) : SV_Target
            {
                float3 positionWS = input.positionWSAndFogFactor.xyz;
                half3 viewDirectionWS = SafeNormalize(GetCameraPositionWS() - positionWS);

#ifdef _MAIN_LIGHT_SHADOWS
                Light mainLight = GetMainLight(input.shadowCoord);
#else
                Light mainLight = GetMainLight();
#endif

                //For toon
                //if you wanted to add bump maps you would add it to this.
                half3 normal = normalize(input.normalWS);
				half3 viewDir = viewDirectionWS;


                float4 additionalLightColors = float4(0,0,0,0);
#ifdef _ADDITIONAL_LIGHTS
                int additionalLightsCount = GetAdditionalLightsCount();
                for (int i = 0; i < additionalLightsCount; ++i)
                {
                    Light light = GetAdditionalLight(i, positionWS);

				    float shadow = 1-light.direction;
                    float NdotL = dot(light.direction, normal);
				    float lightIntensity = smoothstep(0, 0.01, NdotL * shadow);
                    float distAtten = light.distanceAttenuation;
				    additionalLightColors += float4(lightIntensity * light.color * distAtten,1);
                }
#endif


                //NdotL is Normal dot Light direction. use this to determine if something is lit.
				float NdotL = dot(mainLight.direction, normal);

				float shadow = 1-mainLight.direction;

				float lightIntensity = smoothstep(0, 0.01, NdotL * shadow);
				float4 light = float4(lightIntensity * mainLight.color,1);
                
				float3 halfVector = normalize(mainLight.direction + viewDir);
				float NdotH = dot(normal, halfVector);

                //Specular - that dot that you see, it makes things look glossy.
				float specularIntensity = pow(NdotH * lightIntensity, _Glossiness * _Glossiness);
				float specularIntensitySmooth = smoothstep(0.005, 0.01, specularIntensity);
				float4 specular = specularIntensitySmooth * _SpecularColor;

                //Rim Lighting - this is the (often) bright edge of the lit side of the object.
				float rimDot = 1 - dot(viewDir, normal);
				float rimIntensity = rimDot * pow(NdotL, _RimThreshold);
				rimIntensity = smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimIntensity);
				float4 rim = rimIntensity * _RimColor;

                //this is the texture
                float4 col = tex2D(_MainTex, input.uv);
                //Alpha Clip, so that certain models such as Vroid can use them.
                clip(col.a - _Cutoff);

                //Fog - I turned it off, but feel free to re enable it
                //UNITY_APPLY_FOG(input.fogCoord, col);

                return ((light + additionalLightColors) + specular + rim + ( (1-light) * _ShadowColor)) * col * _AmbientColor;
            }
            ENDHLSL
        }
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/Meta"
    }
    //CustomEditor "UnityEditor.Rendering.Universal.ShaderGUI.LitShader"
}
