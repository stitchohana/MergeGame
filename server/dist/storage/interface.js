"use strict";
// --- Game data types ---
Object.defineProperty(exports, "__esModule", { value: true });
exports.QuestType = exports.ActivityCycle = exports.ResetCycle = exports.TokenType = void 0;
var TokenType;
(function (TokenType) {
    TokenType[TokenType["SPIRIT_STONES"] = 1] = "SPIRIT_STONES";
    TokenType[TokenType["QI"] = 2] = "QI";
    TokenType[TokenType["STAMINA"] = 3] = "STAMINA";
    TokenType[TokenType["EXP"] = 4] = "EXP";
})(TokenType || (exports.TokenType = TokenType = {}));
var ResetCycle;
(function (ResetCycle) {
    ResetCycle[ResetCycle["NEVER"] = 0] = "NEVER";
    ResetCycle[ResetCycle["DAILY"] = 1] = "DAILY";
    ResetCycle[ResetCycle["WEEKLY"] = 2] = "WEEKLY";
})(ResetCycle || (exports.ResetCycle = ResetCycle = {}));
var ActivityCycle;
(function (ActivityCycle) {
    ActivityCycle[ActivityCycle["ONCE"] = 0] = "ONCE";
    ActivityCycle[ActivityCycle["DAILY"] = 1] = "DAILY";
    ActivityCycle[ActivityCycle["WEEKLY"] = 2] = "WEEKLY";
    ActivityCycle[ActivityCycle["MONTHLY"] = 3] = "MONTHLY";
})(ActivityCycle || (exports.ActivityCycle = ActivityCycle = {}));
var QuestType;
(function (QuestType) {
    QuestType[QuestType["MERGE"] = 1] = "MERGE";
    QuestType[QuestType["SPAWN"] = 2] = "SPAWN";
    QuestType[QuestType["CRAFT"] = 3] = "CRAFT";
    QuestType[QuestType["SELL"] = 4] = "SELL";
    QuestType[QuestType["BATTLE_ATTACK"] = 5] = "BATTLE_ATTACK";
    QuestType[QuestType["BATTLE_CLEAR"] = 6] = "BATTLE_CLEAR";
    QuestType[QuestType["BREAKTHROUGH"] = 7] = "BREAKTHROUGH";
    QuestType[QuestType["ANY_ITEM_CONSUME"] = 8] = "ANY_ITEM_CONSUME";
    QuestType[QuestType["MERIDIAN_CIRCULATION"] = 9] = "MERIDIAN_CIRCULATION";
})(QuestType || (exports.QuestType = QuestType = {}));
