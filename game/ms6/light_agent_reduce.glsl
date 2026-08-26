#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer AgentState {
    float values[];
} agents;

layout(set = 0, binding = 1, std430) restrict readonly buffer Parameters {
    float values[];
} parameters;

layout(set = 0, binding = 2, std430) restrict writeonly buffer PartialSums {
    vec4 values[];
} partials;

shared vec4 workgroup_values[64];

void main() {
    uint local_index = gl_LocalInvocationID.x;
    uint agent_index = gl_GlobalInvocationID.x;
    uint agent_count = uint(parameters.values[0]);
    vec4 value = vec4(0.0);
    if (agent_index < agent_count) {
        uint offset = agent_index * 4u;
        value = vec4(
            agents.values[offset],
            agents.values[offset + 1u],
            agents.values[offset + 2u],
            agents.values[offset + 3u]
        );
    }
    workgroup_values[local_index] = value;
    barrier();

    for (uint stride = 32u; stride > 0u; stride >>= 1u) {
        if (local_index < stride) {
            workgroup_values[local_index] += workgroup_values[local_index + stride];
        }
        barrier();
    }
    if (local_index == 0u) {
        partials.values[gl_WorkGroupID.x] = workgroup_values[0];
    }
}
