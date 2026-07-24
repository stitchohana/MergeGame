"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createAuthRequired = createAuthRequired;
exports.signToken = signToken;
const jose_1 = require("jose");
const encoder = new TextEncoder();
function createAuthRequired(jwtSecret) {
    const key = encoder.encode(jwtSecret);
    return async (req, res, next) => {
        const header = req.headers.authorization;
        if (!header || !header.startsWith("Bearer ")) {
            res.status(401).json({ error: "missing_authorization" });
            return;
        }
        const token = header.slice(7);
        try {
            const { payload } = await (0, jose_1.jwtVerify)(token, key, { algorithms: ["HS256"] });
            if (typeof payload.userId !== "string" || typeof payload.deviceId !== "string") {
                throw new Error("invalid_payload");
            }
            req.auth = { userId: payload.userId, deviceId: payload.deviceId };
            await next();
        }
        catch {
            res.status(401).json({ error: "invalid_token" });
        }
    };
}
async function signToken(payload, jwtSecret) {
    return new jose_1.SignJWT(payload)
        .setProtectedHeader({ alg: "HS256", typ: "JWT" })
        .setIssuedAt()
        .setExpirationTime("7d")
        .sign(encoder.encode(jwtSecret));
}
