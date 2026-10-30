// Screen coordinates: deterministic BFS ties prefer right, left, down, then up.
export function findNearestEmptyCell(cols: number, rows: number, startCol: number, startRow: number,
  isEmpty: (col: number, row: number) => boolean): { col: number; row: number } | null {
  const visited=new Set<string>([`${startCol},${startRow}`]);
  const queue:Array<[number,number]>=[[startCol,startRow]];
  for(let head=0;head<queue.length;head++) {
    const [col,row]=queue[head];
    if(isEmpty(col,row))return {col,row};
    for(const [x,y] of [[col+1,row],[col-1,row],[col,row+1],[col,row-1]]) {
      const key=`${x},${y}`;
      if(x>=0&&x<cols&&y>=0&&y<rows&&!visited.has(key)) {
        visited.add(key);queue.push([x,y]);
      }
    }
  }
  return null;
}
