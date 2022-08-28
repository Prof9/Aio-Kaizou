from argparse import ArgumentParser
import struct

parser = ArgumentParser()
parser.add_argument('file')
args = parser.parse_args()

print('File: '+args.file)

with open(args.file, 'r+b') as f:
	f.seek(6)
	checksumAddr, = struct.unpack('<H', f.read(2))
	f.seek(checksumAddr+4)
	checksum = sum(f.read())
	f.seek(checksumAddr)
	f.write(struct.pack('<I', checksum))

print('Wrote checksum: '+hex(checksum))
