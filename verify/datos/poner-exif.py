# Inserta un bloque EXIF de prueba (Canon EOS R6, 14/07/2024, GPS de Cusco) en un JPEG.
import struct,sys
p=sys.argv[1]; d=open(p,'rb').read()
def ent(tag,typ,n,val): return struct.pack('<HHI',tag,typ,n)+val
make=b'Canon\0'; model=b'Canon EOS R6\0'; fecha=b'2024:07:14 17:42:05\0'
ifd0_n=4; o=8+2+ifd0_n*12+4
off_make=o; o+=len(make); off_model=o; o+=len(model)
exif_off=o; exif_n=5; o+=2+exif_n*12+4
off_fecha=o; o+=len(fecha); off_exp=o; o+=8; off_f=o; o+=8; off_fl=o; o+=8
gps_off=o; gps_n=4; o+=2+gps_n*12+4; off_lat=o; o+=24; off_lon=o; o+=24
t=b'II*\0'+struct.pack('<I',8)+struct.pack('<H',ifd0_n)
t+=ent(0x10F,2,len(make),struct.pack('<I',off_make))+ent(0x110,2,len(model),struct.pack('<I',off_model))
t+=ent(0x8769,4,1,struct.pack('<I',exif_off))+ent(0x8825,4,1,struct.pack('<I',gps_off))
t+=struct.pack('<I',0)+make+model+struct.pack('<H',exif_n)
t+=ent(0x829A,5,1,struct.pack('<I',off_exp))+ent(0x829D,5,1,struct.pack('<I',off_f))+ent(0x8827,3,1,struct.pack('<HH',400,0))
t+=ent(0x9003,2,len(fecha),struct.pack('<I',off_fecha))+ent(0x920A,5,1,struct.pack('<I',off_fl))
t+=struct.pack('<I',0)+fecha+struct.pack('<II',1,250)+struct.pack('<II',28,10)+struct.pack('<II',50,1)
t+=struct.pack('<H',gps_n)+ent(1,2,2,b'S\0\0\0')+ent(2,5,3,struct.pack('<I',off_lat))+ent(3,2,2,b'W\0\0\0')+ent(4,5,3,struct.pack('<I',off_lon))
t+=struct.pack('<I',0)+struct.pack('<IIIIII',13,1,9,1,3000,100)+struct.pack('<IIIIII',71,1,58,1,1200,100)
app1=b'Exif\0\0'+t
open(p,'wb').write(d[:2]+b'\xff\xe1'+struct.pack('>H',len(app1)+2)+app1+d[2:])
