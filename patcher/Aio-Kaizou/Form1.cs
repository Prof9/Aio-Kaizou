using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace AioKaizou {
	public partial class Form1 : Form {
		private static readonly byte[] MSG_DATA = {
			0x02,0x00,0xF1,0xF0,0x00,0x00,0xF9,0x03,0xC3,0x01,0xF8,0x01,0x00,0xE0,0xF8,0x01,
			0x01,0x1C,0xF8,0x01,0x02,0x00,0xF8,0x01,0x03,0x47,0xFF,0x35,0x10,0x6A,0x54,0x30,
			0x01,0xB5,0x52,0x46,0x12,0x6F,0x10,0x78,0xFF,0x28,0x01,0xD1,0x07,0x32,0x10,0x78,
			0xA9,0x8C,0xC9,0x08,0x04,0xD3,0x01,0x30,0x85,0x28,0x00,0xDD,0x85,0x38,0x10,0x70,
			0x85,0x28,0x00,0xD1,0x00,0x20,0xE9,0x6C,0xE8,0x64,0x88,0x42,0x01,0xD0,0x18,0x3C,
			0x6C,0x63,0xFE,0xB4,0x00,0x49,0x08,0x47,0x13,0x65,0x00,0x08,
		};

		private enum GameVersion {
			JPNv10,
			JPNv11,
			USA,
			EUR
		}

		public Form1() {
			InitializeComponent();
		}

		private void button1_Click(object sender, EventArgs e) {
			GameVersion ver = 0;
			if (radioButton1.Checked) {
				ver = GameVersion.JPNv10;
			} else if (radioButton2.Checked) {
				ver = GameVersion.JPNv11;
			} else if (radioButton3.Checked) {
				ver = GameVersion.USA;
			} else if (radioButton4.Checked) {
				ver = GameVersion.EUR;
			} else {
				if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
					MessageBox.Show("ROMバージョンを選んでください！");
				} else {
					MessageBox.Show("Please select a ROM version!");
				}
				return;
			}

			if (saveFileDialog1.ShowDialog() != DialogResult.OK) {
				return;
			}

			try {
				using (FileStream fs = new FileStream(saveFileDialog1.FileName, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) {
					byte[] save = new byte[0x8000];
					if (fs.Length < save.Length) {
						if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
							throw new Exception("無効なエグゼ４セーブファイル　（ファイルが短すぎます）");
						} else {
							throw new Exception("Not a valid MMBN4/EXE4 save file (file too short)");
						}
					}
					fs.Position = 0;
					fs.Read(save, 0, save.Length);

					EnDecrypt(save);

					int shuffle = BitConverter.ToInt32(save, 0x1550);
					if (shuffle < 0 || shuffle > 0x1FC || (shuffle & 3) != 0) {
						if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
							throw new Exception("無効なエグゼ４セーブファイル　（無効なシャッフルオフセット）");
						} else {
							throw new Exception("Not a valid MMBN4/EXE4 save file (invalid shuffle offset)");
						}
					}

					bool bluemoon;
					uint checksum = BitConverter.ToUInt32(save, 0x21E8 + shuffle);
					uint checksumRS = CalcChecksum(save, shuffle, ver == GameVersion.USA || ver == GameVersion.EUR, false);
					uint checksumBM = CalcChecksum(save, shuffle, ver == GameVersion.USA || ver == GameVersion.EUR, true);
					if (checksum == checksumRS) {
						bluemoon = false;
					} else if (checksum == checksumBM) {
						bluemoon = true;
					} else {
						if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
							throw new Exception("無効なエグゼ４セーブファイル　（チェックサムが一致しません）");
						} else {
							throw new Exception("Not a valid MMBN4/EXE4 save file (checksum does not match)");
						}
					}

					if (!CheckSaveString(save, 0x2208 + shuffle, "ROCKMANEXE4 20031022")) {
						if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
							throw new Exception("無効なエグゼ４セーブファイル　（ゲームタイトルがありません）");
						} else {
							throw new Exception("Not a valid MMBN4/EXE4 save file (missing game title)");
						}
					}

					WriteMsgData(save, ver);

					// Set card numbers.
					for (int i = 0; i < 6; i++) {
						save[0x4644 + shuffle + i] = 0x00;
						save[0x464C + shuffle + i] = 0xFF;
						save[0x4653 + shuffle + i] = 0x85;
					}

					// Unlock all cards.
					for (int i = 1; i <= 133; i++) {
						save[0x5D14 + shuffle + i] = (byte)(save[0x03D0 + i] ^ (bluemoon ? 0x31 : 0x43));
					}

					// Enable kaizou menu.
					SetFlag(save, shuffle, 0x0072, true);

					checksum = CalcChecksum(save, shuffle, ver == GameVersion.USA || ver == GameVersion.EUR, bluemoon);
					Array.Copy(BitConverter.GetBytes(checksum), 0, save, 0x21E8 + shuffle, sizeof(uint));

					EnDecrypt(save);

					fs.Position = 0;
					fs.Write(save, 0, save.Length);
				}
				if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
					MessageBox.Show("成功！");
				} else {
					MessageBox.Show("Success!");
				}
			} catch (Exception ex) {
				if (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja") {
					MessageBox.Show("エラー：　" + ex.Message);
				} else {
					MessageBox.Show("Error: " + ex.Message);
				}
			}
		}

		private void EnDecrypt(byte[] save) {
			uint seed = BitConverter.ToUInt32(save, 0x1554);
			for (int i = 0; i < 0x73D2; i++) {
				save[i] ^= (byte)seed;
			}
			Array.Copy(BitConverter.GetBytes(seed), 0, save, 0x1554, sizeof(uint));
		}

		private int GetShuffledAddr(byte[] save, int addr) {
			int offset = BitConverter.ToInt32(save, 0x1550) & 0x1FC;
			return addr + offset;
		}

		private void SetFlag(byte[] save, int shuffle, int flag, bool value) {
			int addr = 0x2248 + shuffle + (flag >> 3);
			int mask = 0x80 >> (flag & 0x7);
			if (value) {
				save[addr] |= (byte)mask;
			} else {
				save[addr] ^= (byte)~mask;
			}
		}

		private uint CalcChecksum(byte[] save, int shuffle, bool eng, bool bm) {
			uint checksum = bm ? (uint)0x22 : (uint)0x16;
			for (int i = eng ? 0 : 1; i < 0x73D2; i++) {
				if (i == 0x21E8 + shuffle) {
					i += 3;
					continue;
				}
				checksum += save[i];
			}
			return checksum;
		}

		private bool CheckSaveString(byte[] save, int addr, string str) {
			byte[] bytes = new ASCIIEncoding().GetBytes(str);
			for (int i = 0; i < bytes.Length; i++) {
				if (save[addr + i] != bytes[i]) {
					return false;
				}
			}
			return true;
		}

		private void WriteMsgData(byte[] save, GameVersion ver) {
			for (int i = 0; i < 6; i++) {
				for (int j = 0; j < 0x5C; j += 2) {
					ushort s = BitConverter.ToUInt16(MSG_DATA, j);
					if (j == 0x26 || j == 0x2E || j == 0x3E) {
						s += (ushort)(i << 6);
					}
					if (j == 0x58) {
						switch (ver) {
						case GameVersion.JPNv10:
							s = 0x64EF;
							break;
						case GameVersion.JPNv11:
							s = 0x64F3;
							break;
						case GameVersion.USA:
							s = 0x6513;
							break;
						case GameVersion.EUR:
							s = 0x650B;
							break;
						}
					}
					save[0x1EA0 + i * 0x5C + j] = (byte)s;
					save[0x1EA0 + i * 0x5C + j + 1] = (byte)(s >> 8);
				}
			}
		}
	}
}
