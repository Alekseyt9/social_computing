#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer AgentState {
    float values[];
} agents;

layout(set = 0, binding = 1, std430) restrict readonly buffer Parameters {
    float values[];
} parameters;

void main() {
    uint agent_index = gl_GlobalInvocationID.x;
    uint agent_count = uint(parameters.values[0]);
    if (agent_index >= agent_count) {
        return;
    }
    uint offset = agent_index * 4u;
    float wealth = agents.values[offset];
    float stress = agents.values[offset + 1u];
    float spending = agents.values[offset + 2u];
    float activity = agents.values[offset + 3u];
    float stress_delta = parameters.values[1];
    float wealth_delta = parameters.values[2];
    float spending_sensitivity = parameters.values[3];

    stress = clamp(stress + stress_delta * (1.0 - wealth), 0.0, 1.0);
    spending = clamp(
        spending * (1.0 - stress * spending_sensitivity) + wealth_delta * 0.1,
        0.0, 1.0
    );
    wealth = clamp(wealth + wealth_delta - spending * 0.002, 0.0, 1.0);
    activity = clamp(activity + (spending - 0.5) * 0.01, 0.0, 1.0);

    agents.values[offset] = wealth;
    agents.values[offset + 1u] = stress;
    agents.values[offset + 2u] = spending;
    agents.values[offset + 3u] = activity;
}
