pub fn isAlpha(byte: u8) bool {
    return (byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z');
}

pub fn isNumeric(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

pub fn isAlphaNumeric(byte: u8) bool {
    return isAlpha(byte) or isNumeric(byte);
}

pub fn isHexDigit(byte: u8) bool {
    return (byte >= 'A' and byte <= 'F') or (byte >= 'a' and byte <= 'f');
}

pub fn isBinaryDigit(byte: u8) bool {
    return byte == '0' or byte == '1';
}

pub fn isOneOf(byte: u8, characters: []const u8) bool {
    for (characters) |ch| {
        if (byte == ch) return true;
    }

    return false;
}
