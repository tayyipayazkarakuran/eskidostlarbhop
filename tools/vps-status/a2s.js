import dgram from "node:dgram";

const A2S_INFO = Buffer.concat([
  Buffer.from([0xff, 0xff, 0xff, 0xff, 0x54]),
  Buffer.from("Source Engine Query\0", "binary"),
]);

export async function queryGoldSrcServer({ host, port = 27015, timeoutMs = 2500 }) {
  const info = await queryInfo({ host, port, timeoutMs });
  let players = [];
  try {
    players = await queryPlayers({ host, port, timeoutMs });
  } catch {}

  return {
    online: true,
    server: {
      name: info.name,
      map: info.map,
      game: info.game,
      folder: info.folder,
      players: info.players,
      maxPlayers: info.maxPlayers,
      bots: info.bots,
      address: `${host}:${port}`,
      version: info.version,
    },
    players,
    fetchedAt: Math.floor(Date.now() / 1000),
  };
}

export function parseInfoResponse(buffer) {
  const reader = new BufferReader(buffer);
  const header = reader.int32();
  const type = reader.byte();
  if (header !== -1 || type !== 0x49) throw new Error("Invalid A2S_INFO response");

  const protocol = reader.byte();
  const name = reader.string();
  const map = reader.string();
  const folder = reader.string();
  const game = reader.string();
  const appId = reader.uint16();
  const players = reader.byte();
  const maxPlayers = reader.byte();
  const bots = reader.byte();
  const serverType = reader.char();
  const environment = reader.char();
  const visibility = reader.byte();
  const vac = reader.byte();
  const version = reader.string();

  return {
    protocol,
    name,
    map,
    folder,
    game,
    appId,
    players,
    maxPlayers,
    bots,
    serverType,
    environment,
    visibility,
    vac,
    version,
  };
}

export function parsePlayersResponse(buffer) {
  const reader = new BufferReader(buffer);
  const header = reader.int32();
  const type = reader.byte();
  if (header !== -1 || type !== 0x44) throw new Error("Invalid A2S_PLAYER response");

  const count = reader.byte();
  const players = [];
  for (let i = 0; i < count && !reader.done(); i += 1) {
    const index = reader.byte();
    const name = reader.string();
    const score = reader.int32();
    const duration = reader.float();
    players.push({ index, name, score, duration });
  }
  return players;
}

async function queryInfo({ host, port, timeoutMs }) {
  const response = await udpRoundTrip({ host, port, payload: A2S_INFO, timeoutMs });
  return parseInfoResponse(response);
}

async function queryPlayers({ host, port, timeoutMs }) {
  const challengeRequest = Buffer.alloc(9);
  challengeRequest.writeInt32LE(-1, 0);
  challengeRequest.writeUInt8(0x55, 4);
  challengeRequest.writeInt32LE(-1, 5);

  const challengeResponse = await udpRoundTrip({ host, port, payload: challengeRequest, timeoutMs });
  if (challengeResponse.readInt32LE(0) !== -1 || challengeResponse.readUInt8(4) !== 0x41) {
    return parsePlayersResponse(challengeResponse);
  }

  const challenge = challengeResponse.readInt32LE(5);
  const playerRequest = Buffer.alloc(9);
  playerRequest.writeInt32LE(-1, 0);
  playerRequest.writeUInt8(0x55, 4);
  playerRequest.writeInt32LE(challenge, 5);
  return parsePlayersResponse(await udpRoundTrip({ host, port, payload: playerRequest, timeoutMs }));
}

function udpRoundTrip({ host, port, payload, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const socket = dgram.createSocket("udp4");
    const timeout = setTimeout(() => {
      socket.close();
      reject(new Error("A2S query timed out"));
    }, timeoutMs);

    socket.once("message", (message) => {
      clearTimeout(timeout);
      socket.close();
      resolve(message);
    });
    socket.once("error", (error) => {
      clearTimeout(timeout);
      socket.close();
      reject(error);
    });
    socket.send(payload, port, host);
  });
}

class BufferReader {
  constructor(buffer) {
    this.buffer = buffer;
    this.offset = 0;
  }

  done() {
    return this.offset >= this.buffer.length;
  }

  byte() {
    const value = this.buffer.readUInt8(this.offset);
    this.offset += 1;
    return value;
  }

  char() {
    return String.fromCharCode(this.byte());
  }

  uint16() {
    const value = this.buffer.readUInt16LE(this.offset);
    this.offset += 2;
    return value;
  }

  int32() {
    const value = this.buffer.readInt32LE(this.offset);
    this.offset += 4;
    return value;
  }

  float() {
    const value = this.buffer.readFloatLE(this.offset);
    this.offset += 4;
    return value;
  }

  string() {
    const end = this.buffer.indexOf(0, this.offset);
    const safeEnd = end >= 0 ? end : this.buffer.length;
    const value = this.buffer.toString("utf8", this.offset, safeEnd);
    this.offset = safeEnd + 1;
    return value;
  }
}
