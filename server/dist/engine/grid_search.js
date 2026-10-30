"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.findNearestEmptyCell = findNearestEmptyCell;
// Screen coordinates: deterministic BFS ties prefer right, left, down, then up.
function findNearestEmptyCell(cols, rows, startCol, startRow, isEmpty) {
    const visited = new Set([`${startCol},${startRow}`]);
    const queue = [[startCol, startRow]];
    for (let head = 0; head < queue.length; head++) {
        const [col, row] = queue[head];
        if (isEmpty(col, row))
            return { col, row };
        for (const [x, y] of [[col + 1, row], [col - 1, row], [col, row + 1], [col, row - 1]]) {
            const key = `${x},${y}`;
            if (x >= 0 && x < cols && y >= 0 && y < rows && !visited.has(key)) {
                visited.add(key);
                queue.push([x, y]);
            }
        }
    }
    return null;
}
