[Vertex]
#version 450 core
layout (location = 0) in vec2 attribPosition;
layout (location = 5) in vec2 attribTexCoord;

out VS_OUT {
	vec2 texCoord;
} frag;

void main() {
	frag.texCoord = attribTexCoord;

	gl_Position = vec4(attribPosition, 0.0, 1.0);
}

[Fragment]
#version 450 core

in VS_OUT {
    vec2 texCoord;
} frag;

out vec4 finalColor;

uniform sampler2D bufferedPosition;
uniform sampler2D bufferedNormal;
uniform sampler2D bufferedAlbedo;
uniform sampler2D shadowMap;

struct Light {
    vec4 position;
    vec4 color;

    float linear;
    float quadratic;
    
    uint mode;
};
const uint DIRECTIONAL_LIGHT = 0;
const uint POINT_LIGHT = 1;
const int MAX_LIGHTS = 128;
const int MAX_SHADOW_CASTERS = 2;
layout (std140 binding = 1) uniform LightingContext {
    Light lights[MAX_LIGHTS];
    uvec4 shadowCasters;                      // IDs of the lights used for shadow mapping
    mat4 matLightSpaces[MAX_SHADOW_CASTERS];  // Space matrices of the lights used for shadow mapping
    vec4 ambient;                             // .rgb for the color and .a for the intensity
    uint lightCount;
    uint shadowCasterCount;
}

float computeShadowValue(vec4 lightSpacePosition, float bias);

vec3 computeDirectionalLighting( Light light, vec3 p, vec3 n, vec3 a );
vec3 computePointLighting( Light light, vec3 p, vec3 n, vec3 a );

void main() {
    vec3 position = texture(bufferedPosition, frag.texCoord).rgb;
    vec3 normal = texture(bufferedNormal, frag.texCoord).rgb;
    vec3 albedo = texture(bufferedAlbedo, frag.texCoord).rgb;

    vec3 ambient = ambient.xyz * ambient.a;
    vec3 result = ambient;
    
    for (int i = 0; i < lightCount; i += 1) {
        Light light = lights[i];

        if (light.mode == DIRECTIONAL_LIGHT) {
            result += computeDirectionalLighting(light, position, normal, albedo);
        } else if (light.mode == POINT_LIGHT) {
            result += computePointLighting(light, position, normal, albedo);
        }
    }
    finalColor = vec4(result, 1.0);
}

vec3 computeDirectionalLighting( Light light, vec3 p, vec3 n, vec3 a ) {
    vec3 lightDir = normalize(light.position);
    float diffuseContribution = max(dot(lightDir, n), 0.0);
    vec3 diffuse = diffuseContribution * light.color;

    vec3 viewDir = normalize(viewPosition - p);
    vec3 reflectDir = reflect(-lightDir, n);
    float specContribution = max(dot(viewDir, reflectDir), 0.0);
    vec3 specular = 0.5 * (specContribution * light.color);

    return (diffuse + specular);
}

vec3 computePointLighting( Light light, vec3 p, vec3 n, vec3 a ) {
    vec3 lightDir = normalize(light.position - p);
    float diffuseContribution = max(dot(lightDir, n), 0.0);
    vec3 diffuse = diffuseContribution * light.color;

    vec3 viewDir = normalize(viewPosition - p);
    vec3 reflectDir = reflect(-lightDir, n);
    float specContribution = max(dot(viewDir, reflectDir), 0.0);
    vec3 specular = 0.5 * (specContribution * light.color);

    float distance = length(light.position - p);
    float attenuation = 1.0 / (1.0 + light.linear * distance + light.quadratic * (pow(distance)));
    return (diffuse * attenuation) + (specular * attenuation);
}

float computeShadowValue(vec4 lightSpacePosition, float bias) {
    vec3 projCoord = lightSpacePosition.xyz / lightSpacePosition.w;
    if (projCoord.z > 1.0) {
        return 0.0;
    }
    projCoord = projCoord * 0.5 + 0.5;
    float currentDepth = projCoord.z;

    float result = 0.0;
    vec2 texelSize = 1.0 / textureSize(mapShadow, 0);
    for (int x = -1; x <= 1; x += 1) {
        for (int y = -1; y <= 1; y += 1) {
            vec2 pcfCoord = projCoord.xy + vec2(x, y) * texelSize;
            float pcfDepth = texture(mapShadow, pcfCoord).r;
            result += currentDepth - bias > pcfDepth ? 1.0 : 0.0;
        }
    }
    result /= 9.0;
    return result;
}