[Vertex]
#version 450 core
layout (location = 0) in vec3 attribPosition;
layout (location = 1) in vec3 attribNormal;
layout (location = 2) in vec3 attribTangent;
layout (location = 5) in vec2 attribTexCoord;

out VS_OUT {
	vec3 position;
	vec3 normal;
	vec2 texCoord;
	vec3 tanLightPosition;
	vec3 tanViewPosition;
	vec3 tanPosition;
	vec4 lightSpacePosition;
	vec4 clipSpacePosition;
} frag;

uniform mat4 mvp;
uniform mat4 matModel;
uniform mat3 matNormal;

layout (std140, binding = 0) uniform ContextData {
    mat4 projView;
    mat4 matProj;
    mat4 matView;
    vec3 viewPosition;
    float time;
    float dt;
};


struct Light {
	uint on;
	vec3 position;
	vec3 color;
};
layout (std140, binding = 1) uniform Lights {
	Light lights[4];
	mat4 matLightSpace;
	vec3 ambientClr;
	float ambientStrength;
};

void main()
{
	frag.position = vec3(matModel * vec4(attribPosition, 1.0));
	frag.clipSpacePosition = projView * matModel * vec4(attribPosition, 1.0);
	frag.normal = matNormal * attribNormal;
	frag.texCoord = attribTexCoord;
	frag.lightSpacePosition = matLightSpace * matModel * vec4(attribPosition, 1.0);

	vec3 t = normalize(matNormal * vec3(attribTangent));
	vec3 n = normalize(matNormal * attribNormal);
	t =  normalize(t - dot(t, n) * n);
	vec3 b = cross(n, t);

	mat3 tbn = transpose(mat3(t, b, n));
	frag.tanLightPosition = tbn * lights[0].position;
	frag.tanViewPosition = tbn * viewPosition;
	frag.tanPosition = tbn * frag.position;

    gl_Position = mvp*vec4(attribPosition, 1.0);
} 

[Fragment]
#version 450 core
in VS_OUT {
	vec3 position;
	vec3 normal;
	vec2 texCoord;
	vec3 tanLightPosition;
	vec3 tanViewPosition;
	vec3 tanPosition;
	vec4 lightSpacePosition;
	vec4 clipSpacePosition;
} frag;

out vec4 finalColor;

layout (std140, binding = 0) uniform ContextData {
    mat4 projView;
    mat4 matProj;
    mat4 matView;
    vec3 viewPosition;
    float time;
    float dt;
};


struct Light {
	uint on;
	vec3 position;
	vec3 color;
};
layout (std140, binding = 1) uniform Lights {
	Light lights[4];
	mat4 matLightSpace;
	vec3 ambientClr;
	float ambientStrength;
};

uniform sampler2D texture0;
uniform sampler2D texture1;
uniform sampler2D mapViewDepth;

float linearDepthValue(float near, float far, float depth);

vec2 fade(vec2 t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }

vec4 rand4(vec4 p) { return mod(((p * 34.0) + 1.0) * p, 289.0); }

float perlin(vec2 P) {
  vec4 Pi = floor(P.xyxy) + vec4(0.0, 0.0, 1.0, 1.0);
  vec4 Pf = fract(P.xyxy) - vec4(0.0, 0.0, 1.0, 1.0);
  Pi = mod(Pi, 289.0); // To avoid truncation effects in permutation
  vec4 ix = Pi.xzxz;
  vec4 iy = Pi.yyww;
  vec4 fx = Pf.xzxz;
  vec4 fy = Pf.yyww;
  vec4 i = rand4(rand4(ix) + iy);
  vec4 gx = 2.0 * fract(i * 0.0243902439) - 1.0; // 1/41 = 0.024...
  vec4 gy = abs(gx) - 0.5;
  vec4 tx = floor(gx + 0.5);
  gx = gx - tx;
  vec2 g00 = vec2(gx.x, gy.x);
  vec2 g10 = vec2(gx.y, gy.y);
  vec2 g01 = vec2(gx.z, gy.z);
  vec2 g11 = vec2(gx.w, gy.w);
  vec4 norm =
      1.79284291400159 - 0.85373472095314 * vec4(dot(g00, g00), dot(g01, g01),
                                                 dot(g10, g10), dot(g11, g11));
  g00 *= norm.x;
  g01 *= norm.y;
  g10 *= norm.z;
  g11 *= norm.w;
  float n00 = dot(g00, vec2(fx.x, fy.x));
  float n10 = dot(g10, vec2(fx.y, fy.y));
  float n01 = dot(g01, vec2(fx.z, fy.z));
  float n11 = dot(g11, vec2(fx.w, fy.w));
  vec2 fade_xy = fade(Pf.xy);
  vec2 n_x = mix(vec2(n00, n01), vec2(n10, n11), fade_xy.x);
  float n_xy = mix(n_x.x, n_x.y, fade_xy.y);
  return 2.3 * n_xy;
}

void main()
{
	const float near = 0.1;
	const float far = 100;
	const float normalScrollSpeed = 0.01;

	const vec3 shallowWaterClr = vec3(0.325, 0.658, 0.84);
	const vec3 deepWaterClr = vec3(0.07, 0.325, 0.71);
	const float transparentMaxDepth = 1.0;
	const float minTransparency = 0.65;
	const float foamTransparency = 0.25;


	float scrollValue = time * normalScrollSpeed;
	vec3 tanNormal = texture(texture1, frag.texCoord + vec2(scrollValue)).rgb;
	tanNormal = normalize(tanNormal * 2.0 - 1.0);
	vec3 tanLightDir = normalize(frag.tanLightPosition);
	float diffuseValue = max(dot(tanLightDir, tanNormal), 0.0);
	vec3 diffuse = diffuseValue * lights[0].color;

	vec3 ambient = ambientStrength * ambientClr;

	vec3 viewDir = normalize(frag.tanViewPosition - frag.tanPosition);
	vec3 reflectDir = reflect(-tanLightDir, tanNormal);
	float specValue = max(dot(viewDir, reflectDir), 0.0);
	specValue = pow(specValue, 32);
	vec3 specular = (specValue * lights[0].color);
	vec3 specular2 = max(smoothstep(0.6, 0.8, specular), 0.25);

	// vec3 normal = normalize(frag.normal);
	// vec3 lightDir = normalize(lights[0].position);
	// viewDir = normalize(viewPosition - frag.position);
	// reflectDir = reflect(-lightDir, normal);
	// specValue = max(dot(viewDir, reflectDir), 0.0);
	// vec3 specular2 = specValue * lights[0].color;

	// float diffuseValue = max(dot(lightDir, frag.position), 0.0);
	// vec3 diffuse = diffuseValue * lights[0].color.rgb;
	

	vec3 depthCoord  = frag.clipSpacePosition.xyz / frag.clipSpacePosition.w;
	depthCoord = (depthCoord * 0.5) + 0.5;
	float result = texture(mapViewDepth, depthCoord.xy).r;
	float linearDepth = linearDepthValue(near, far, result);

	float viewWaterDepth = linearDepthValue(near, far, gl_FragCoord.z);
	float waterDepth = (linearDepth - viewWaterDepth) * 25;

	const float cutoffMin = 0.5; 
	const float cutoffMax = 1.5;
	const float cutoffRange = 0.1;
	float noise = perlin(vec2(frag.clipSpacePosition.x * time, frag.clipSpacePosition.z * time)) * cutoffRange;
	waterDepth = smoothstep(cutoffMin + noise, cutoffMax + noise, waterDepth);

	float normWaterDepth = min((linearDepth - viewWaterDepth) / transparentMaxDepth, 1.0);
	float waterTransparency = max(foamTransparency - waterDepth, normWaterDepth);
	waterTransparency = smoothstep(0.05, 0.7, waterTransparency) + minTransparency;

	vec3 waterClr = mix(shallowWaterClr, deepWaterClr, min((linearDepth - viewWaterDepth) / 2.0, 1.0));
	vec3 depthClr = waterClr * waterDepth + vec3(1.0) * (1.0 - waterDepth);
	depthClr.r = clamp(depthClr.r, waterClr.r, 1.0);
	depthClr.g = clamp(depthClr.g, waterClr.g, 1.0);
	depthClr.b = clamp(depthClr.b, waterClr.b, 1.0);

	vec3 resultClr = (1.0 + specular2) * depthClr + smoothstep(0.85, 0.95, specular);
	finalColor = vec4(resultClr, waterTransparency);
}

float linearDepthValue(float near, float far, float depth) {
    float result = 2.0 * near * far / (far + near - (2.0 * depth - 1.0) * (far - near));
    return result;
}
