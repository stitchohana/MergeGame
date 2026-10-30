export declare function findNearestEmptyCell(cols: number, rows: number, startCol: number, startRow: number, isEmpty: (col: number, row: number) => boolean): {
    col: number;
    row: number;
} | null;
