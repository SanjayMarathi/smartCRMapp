from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
draw.rounded_rectangle([0, 0, 512, 512], radius=128, fill='#10B981')
try:
    font = ImageFont.truetype('arialbd.ttf', 300)
except:
    font = ImageFont.load_default(size=300)
draw.text((256, 240), 'S', font=font, fill='white', anchor='mm')
img.save('e:/smartCRMapp/assets/branding/smartcmr_logo.png')
