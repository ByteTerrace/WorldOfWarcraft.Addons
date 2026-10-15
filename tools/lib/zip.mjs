// Zip archives, as package writes them: deflated files with UTF-8 names, a directory entry for
// each folder, and one timestamp for every entry (the commit's), so the same commit always
// makes the same bytes. No zip64: a package is far below its 4 GB limits. readZip reads back
// what writeZip writes (stored or deflated entries, no comment), which the tooling's tests use.

import { deflateRawSync, inflateRawSync } from "node:zlib";

const LOCAL = 0x04034b50;
const CENTRAL = 0x02014b50;
const END = 0x06054b50;
const UTF8 = 0x0800;
const DIRECTORY = 0x10;

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
});

export function crc32(data) {
    let c = 0xffffffff;
    for (const byte of data) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}

// A Date as MS-DOS time and date fields, in UTC (2-second resolution, years 1980 to 2107).
function dosTime(date) {
    const year = Math.min(Math.max(date.getUTCFullYear(), 1980), 2107);
    return {
        time: (date.getUTCHours() << 11) | (date.getUTCMinutes() << 5) | Math.floor(date.getUTCSeconds() / 2),
        date: ((year - 1980) << 9) | ((date.getUTCMonth() + 1) << 5) | date.getUTCDate(),
    };
}

// The bytes of a zip holding entries [{ path, data }] (path with "/" separators, data a Buffer or
// string), with a directory entry for every folder they sit in, all stamped with date.
export function writeZip(entries, date = new Date(0)) {
    const folders = new Set();
    for (const { path } of entries) {
        const parts = path.split("/").slice(0, -1);
        for (let i = 1; i <= parts.length; i++) folders.add(parts.slice(0, i).join("/") + "/");
    }
    const all = [
        ...[...folders].sort().map((path) => ({ path, data: Buffer.alloc(0), directory: true })),
        ...entries.map(({ path, data }) => ({ path, data: Buffer.from(data), directory: false })),
    ];
    const { time, date: day } = dosTime(date);
    const locals = [];
    const centrals = [];
    let offset = 0;
    for (const entry of all) {
        const name = Buffer.from(entry.path, "utf8");
        const method = entry.directory ? 0 : 8;
        const body = entry.directory ? entry.data : deflateRawSync(entry.data, { level: 9 });
        const crc = crc32(entry.data);
        const local = Buffer.alloc(30);
        local.writeUInt32LE(LOCAL, 0);
        local.writeUInt16LE(20, 4);
        local.writeUInt16LE(UTF8, 6);
        local.writeUInt16LE(method, 8);
        local.writeUInt16LE(time, 10);
        local.writeUInt16LE(day, 12);
        local.writeUInt32LE(crc, 14);
        local.writeUInt32LE(body.length, 18);
        local.writeUInt32LE(entry.data.length, 22);
        local.writeUInt16LE(name.length, 26);
        const central = Buffer.alloc(46);
        central.writeUInt32LE(CENTRAL, 0);
        central.writeUInt16LE(20, 4);
        central.writeUInt16LE(20, 6);
        central.writeUInt16LE(UTF8, 8);
        central.writeUInt16LE(method, 10);
        central.writeUInt16LE(time, 12);
        central.writeUInt16LE(day, 14);
        central.writeUInt32LE(crc, 16);
        central.writeUInt32LE(body.length, 20);
        central.writeUInt32LE(entry.data.length, 24);
        central.writeUInt16LE(name.length, 28);
        central.writeUInt32LE(entry.directory ? DIRECTORY : 0, 38);
        central.writeUInt32LE(offset, 42);
        locals.push(local, name, body);
        centrals.push(central, name);
        offset += local.length + name.length + body.length;
    }
    const directory = Buffer.concat(centrals);
    const end = Buffer.alloc(22);
    end.writeUInt32LE(END, 0);
    end.writeUInt16LE(all.length, 8);
    end.writeUInt16LE(all.length, 10);
    end.writeUInt32LE(directory.length, 12);
    end.writeUInt32LE(offset, 16);
    return Buffer.concat([...locals, directory, end]);
}

// The file entries of a zip writeZip wrote, [{ path, data }] in archive order, directories left
// out. Throws on a CRC mismatch or a layout it doesn't read.
export function readZip(bytes) {
    const endAt = bytes.length - 22;
    if (endAt < 0 || bytes.readUInt32LE(endAt) !== END) throw new Error("not a zip without a comment");
    const count = bytes.readUInt16LE(endAt + 10);
    let at = bytes.readUInt32LE(endAt + 16);
    const files = [];
    for (let i = 0; i < count; i++) {
        if (bytes.readUInt32LE(at) !== CENTRAL) throw new Error(`no central directory entry at ${at}`);
        const method = bytes.readUInt16LE(at + 10);
        const crc = bytes.readUInt32LE(at + 16);
        const size = bytes.readUInt32LE(at + 20);
        const nameLength = bytes.readUInt16LE(at + 28);
        const extraLength = bytes.readUInt16LE(at + 30);
        const commentLength = bytes.readUInt16LE(at + 32);
        const localAt = bytes.readUInt32LE(at + 42);
        const path = bytes.toString("utf8", at + 46, at + 46 + nameLength);
        at += 46 + nameLength + extraLength + commentLength;
        if (path.endsWith("/")) continue;
        const dataAt = localAt + 30 + bytes.readUInt16LE(localAt + 26) + bytes.readUInt16LE(localAt + 28);
        const body = bytes.subarray(dataAt, dataAt + size);
        const data = method === 8 ? inflateRawSync(body) : Buffer.from(body);
        if (crc32(data) !== crc) throw new Error(`${path}: CRC mismatch`);
        files.push({ path, data });
    }
    return files;
}
