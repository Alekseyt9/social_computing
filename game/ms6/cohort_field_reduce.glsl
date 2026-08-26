#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer AgentFields {
    float values[];
} fields;

layout(set = 0, binding = 1, std430) restrict readonly buffer CohortCodes {
    int values[];
} cohort_codes;

layout(set = 0, binding = 2, std430) restrict readonly buffer Parameters {
    float values[];
} parameters;

layout(set = 0, binding = 3, std430) restrict writeonly buffer CohortTotals {
    float values[];
} totals;

shared vec4 field_sums[64];
shared float agent_counts[64];

void main() {
    uint local_index = gl_LocalInvocationID.x;
    uint cohort_index = gl_WorkGroupID.x;
    uint agent_count = uint(parameters.values[0]);
    vec4 sum = vec4(0.0);
    float count = 0.0;
    for (uint agent_index = local_index; agent_index < agent_count; agent_index += 64u) {
        if (cohort_codes.values[agent_index] == int(cohort_index)) {
            uint offset = agent_index * 4u;
            sum += vec4(
                fields.values[offset], fields.values[offset + 1u],
                fields.values[offset + 2u], fields.values[offset + 3u]
            );
            count += 1.0;
        }
    }
    field_sums[local_index] = sum;
    agent_counts[local_index] = count;
    barrier();
    for (uint stride = 32u; stride > 0u; stride >>= 1u) {
        if (local_index < stride) {
            field_sums[local_index] += field_sums[local_index + stride];
            agent_counts[local_index] += agent_counts[local_index + stride];
        }
        barrier();
    }
    if (local_index == 0u) {
        uint output_offset = cohort_index * 5u;
        totals.values[output_offset] = field_sums[0].x;
        totals.values[output_offset + 1u] = field_sums[0].y;
        totals.values[output_offset + 2u] = field_sums[0].z;
        totals.values[output_offset + 3u] = field_sums[0].w;
        totals.values[output_offset + 4u] = agent_counts[0];
    }
}
