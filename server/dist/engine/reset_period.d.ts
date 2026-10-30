/** Game calendar: Beijing time (UTC+8), with each day starting at resetHour. */
export declare function getResetPeriod(timestamp: number, resetHour: number): {
    day: string;
    week: string;
    month: string;
    weekday: number;
};
