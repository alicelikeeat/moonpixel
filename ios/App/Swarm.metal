#include <metal_stdlib>
using namespace metal;

// The nanite swarm. Every point is simulated here, on the GPU: a compute pass moves all of them
// (a spring towards the point's place in the current shape, a swirl and a wobble while it is free),
// then they are drawn as round grains. Shapes come from MoonPixelCore (Swarm.swift): x, y, z and a
// colour packed into the bits of w. Space is tile units around the swarm's origin, y up.

struct SwarmUniforms {
    float4 right;    // xyz: the camera's right in swarm space; w: one tile in NDC along x
    float4 up;       // xyz: the camera's up;                   w: one tile in NDC along y
    float4 fwd;      // xyz: into the picture;                  w: grain size in pixels
    float4 center;   // xy: where the swarm's origin is on screen (NDC); z: time; w: time step
    float4 params;   // x: pull towards the shape (0 free, 1 held); y: blend from shape A to B; z: scatter; w: count
    float4 travel;   // x: how far the pouring-in has come (0...1)
};

static float3 unpackColor(float w) {
    uint v = as_type<uint>(w);
    return float3(float(v & 255), float((v >> 8) & 255), float((v >> 16) & 255)) / 255.0;
}

kernel void swarmStep(device float4 *pos [[buffer(0)]],
                      device float4 *vel [[buffer(1)]],
                      const device float4 *shapeA [[buffer(2)]],
                      const device float4 *shapeB [[buffer(3)]],
                      constant SwarmUniforms &u [[buffer(4)]],
                      uint id [[thread_position_in_grid]]) {
    if (id >= uint(u.params.w)) { return; }
    float4 p = pos[id];
    float3 v = vel[id].xyz;
    float seed = p.w;                                   // a random number of this point's own, 0...1
    float t = u.center.z, dt = u.center.w;
    float3 target = mix(shapeA[id].xyz, shapeB[id].xyz, u.params.y);
    // every point sets out a little later than the one before: the swarm pours, it does not jump
    float pull = u.params.x * smoothstep(0.0, 1.0, saturate(u.travel.x * 1.6 - seed * 0.6));
    float3 d = p.xyz - float3(0.0, p.y, 0.0);
    float3 swirl = float3(-d.z, 0.0, d.x) * (0.35 + seed * 0.4);
    float3 wob = float3(sin(t * 3.1 + seed * 40.0), cos(t * 2.3 + seed * 31.0), sin(t * 2.7 + seed * 17.0)) * 0.6;
    float3 acc = (target - p.xyz) * (38.0 * pull) + swirl * (1.0 - pull) * 1.5 + wob * (1.0 - 0.8 * pull);
    if (u.params.z > 0.5) {                             // the show is over: everything flies apart and falls
        float3 out = p.xyz - float3(0.0, 2.0, 0.0) + wob * 0.2;
        acc = normalize(out + float3(0.0001, 0.0, 0.0)) * (9.0 + seed * 14.0) + float3(0.0, -3.0, 0.0);
    }
    v = (v + acc * dt) * (1.0 - min(0.9, (2.0 + 9.0 * pull) * dt));
    p.xyz += v * dt;
    if (p.y < 0.02) { p.y = 0.02; v.y = abs(v.y) * 0.3; }
    pos[id] = p;
    vel[id] = float4(v, 0.0);
}

struct SwarmPoint {
    float4 position [[position]];
    float size [[point_size]];
    float3 color;
};

vertex SwarmPoint swarmVertex(uint vid [[vertex_id]],
                              const device float4 *pos [[buffer(0)]],
                              const device float4 *vel [[buffer(1)]],
                              const device float4 *shapeA [[buffer(2)]],
                              const device float4 *shapeB [[buffer(3)]],
                              constant SwarmUniforms &u [[buffer(4)]]) {
    float4 p = pos[vid];
    float x = dot(p.xyz, u.right.xyz), y = dot(p.xyz, u.up.xyz), z = dot(p.xyz, u.fwd.xyz);
    SwarmPoint o;
    o.position = float4(u.center.x + x * u.right.w, u.center.y + y * u.up.w, saturate(0.5 + z * 0.02), 1.0);
    o.size = max(1.0, u.fwd.w * (0.75 + 0.5 * p.w));
    float3 shaped = mix(unpackColor(shapeA[vid].w), unpackColor(shapeB[vid].w), u.params.y);
    float3 steel = float3(0.23, 0.29, 0.35) + 0.12 * p.w;
    float speed = length(vel[vid].xyz);
    float3 c = mix(steel, shaped, saturate(u.params.x * (1.0 - u.params.z)));
    o.color = c * (0.72 + 0.28 * p.w) + float3(0.25, 0.5, 0.6) * saturate(speed * 0.06);
    return o;
}

// what the fragment stage takes from a grain (a fragment input may not carry the point size)
struct SwarmGrain {
    float4 position [[position]];
    float3 color;
};

fragment float4 swarmFragment(SwarmGrain in [[stage_in]], float2 pc [[point_coord]]) {
    float2 c = pc - 0.5;
    float r2 = dot(c, c);
    if (r2 > 0.25) { discard_fragment(); }
    return float4(in.color * (1.0 - r2 * 1.6), 1.0);
}
