use std::io::{self, Read, Write};
use prost::Message;

pub fn read_raw_message<R: Read>(reader: &mut R) -> io::Result<Vec<u8>> {
    // Read 4-byte length prefix (little-endian)
    let mut len_buf = [0u8; 4];
    reader.read_exact(&mut len_buf)?;
    let len = u32::from_le_bytes(len_buf) as usize;

    // Read message bytes
    let mut buf = vec![0u8; len];
    reader.read_exact(&mut buf)?;
    Ok(buf)
}

pub fn write_raw_message<W: Write>(writer: &mut W, data: &[u8]) -> io::Result<()> {
    // Write length prefix
    let len = (data.len() as u32).to_le_bytes();
    writer.write_all(&len)?;

    // Write message
    writer.write_all(data)?;
    writer.flush()
}

pub fn read_message<T: Message + Default, R: Read>(reader: &mut R) -> io::Result<T> {
    let buf = read_raw_message(reader)?;
    T::decode(&buf[..]).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

pub fn write_message<T: Message, W: Write>(writer: &mut W, msg: &T) -> io::Result<()> {
    let buf = msg.encode_to_vec();
    write_raw_message(writer, &buf)
}
