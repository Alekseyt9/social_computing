#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Positions {
    float values[];
} positions;

layout(set = 0, binding = 1, std430) restrict readonly buffer Parameters {
    float values[];
} parameters;

layout(set = 0, binding = 2, std430) restrict buffer CellHeads {
    int values[];
} cell_heads;

void main() {
    uint agent_index = gl_GlobalInvocationID.x;
    uint agent_count = uint(parameters.values[0]);
    if (agent_index >= agent_count) {
        return;
    }
    int grid_width = int(parameters.values[1]);
    int grid_height = int(parameters.values[2]);
    float cell_size = parameters.values[3];
    int lane_count = int(parameters.values[5]);
    uint offset = agent_index * 2u;
    int cell_x = clamp(int(floor(positions.values[offset] / cell_size)), 0, grid_width - 1);
    int cell_y = clamp(int(floor(positions.values[offset + 1u] / cell_size)), 0, grid_height - 1);
    int cell_index = cell_y * grid_width + cell_x;
    int lane = int(agent_index) % lane_count;
    atomicMin(cell_heads.values[cell_index * lane_count + lane], int(agent_index));
}
