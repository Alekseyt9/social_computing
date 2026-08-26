#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Positions {
    float values[];
} positions;

layout(set = 0, binding = 1, std430) restrict readonly buffer Parameters {
    float values[];
} parameters;

layout(set = 0, binding = 2, std430) restrict readonly buffer CellHeads {
    int values[];
} cell_heads;

layout(set = 0, binding = 3, std430) restrict writeonly buffer Neighbors {
    int values[];
} neighbors;

void main() {
    uint agent_index = gl_GlobalInvocationID.x;
    uint agent_count = uint(parameters.values[0]);
    if (agent_index >= agent_count) {
        return;
    }
    int grid_width = int(parameters.values[1]);
    int grid_height = int(parameters.values[2]);
    float cell_size = parameters.values[3];
    float radius_squared = parameters.values[4] * parameters.values[4];
    int lane_count = int(parameters.values[5]);
    uint offset = agent_index * 2u;
    vec2 position = vec2(positions.values[offset], positions.values[offset + 1u]);
    int center_x = clamp(int(floor(position.x / cell_size)), 0, grid_width - 1);
    int center_y = clamp(int(floor(position.y / cell_size)), 0, grid_height - 1);
    int best_index = -1;
    float best_distance = radius_squared;

    for (int delta_y = -1; delta_y <= 1; delta_y++) {
        int cell_y = center_y + delta_y;
        if (cell_y < 0 || cell_y >= grid_height) {
            continue;
        }
        for (int delta_x = -1; delta_x <= 1; delta_x++) {
            int cell_x = center_x + delta_x;
            if (cell_x < 0 || cell_x >= grid_width) {
                continue;
            }
            int cell_index = cell_y * grid_width + cell_x;
            for (int lane = 0; lane < lane_count; lane++) {
                int candidate = cell_heads.values[cell_index * lane_count + lane];
                if (candidate < 0 || candidate >= int(agent_count)) {
                    continue;
                }
                if (candidate != int(agent_index)) {
                    uint candidate_offset = uint(candidate) * 2u;
                    vec2 candidate_position = vec2(
                        positions.values[candidate_offset],
                        positions.values[candidate_offset + 1u]
                    );
                    vec2 difference = candidate_position - position;
                    float distance_squared = dot(difference, difference);
                    if (
                        distance_squared <= radius_squared
                        && (
                            best_index < 0 || distance_squared < best_distance
                            || (distance_squared == best_distance && candidate < best_index)
                        )
                    ) {
                        best_distance = distance_squared;
                        best_index = candidate;
                    }
                }
            }
        }
    }
    neighbors.values[agent_index] = best_index;
}
