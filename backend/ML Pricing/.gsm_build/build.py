import csv, math, random, collections, pathlib, zipfile, io
from xml.sax.saxutils import escape
P=pathlib.Path
base='https://www.gsmarena.com/'
sources={
'a16':'apple_iphone_16_series_goes_on_sale-news-64620.php',
'a13':'the_iphone_13_series_goes_on_preorder_later_this_week_here_are_the_prices_from_around_the_world-news-50939.php',
's':'samsung_galaxy_s24_open_sale_begins_today-news-61394.php',
'x':'the_xiaomi_14_and_14_pro_are_here_with_new_design_and_main_leica_cameras-news-60378.php',
'o':'oppo_starts_selling_find_x8_ultra_x8s_and_x8s-news-67429.php',
'h':'honor_magic7_pro_unveiled_with_a_200mp_tele_camera_vanilla_magic7_powered_by_the_sd_8_elite-news-65140.php',
'v':'vivo_x200_x200_pro_china_price_sale_date-news-64995.php',
'r':'realme_gt7_goes_official_with_dimensity_9400_chip_and_7200mah_battery-news-67501.php',
'rr':'realme_gt_7_pro_racing_edition_features_price_sale_date-news-66517.php',
'm':'huawei_mate_70_series_is_now_up_for_preorder_sale_begins_tomorrow-news-65598.php',
'g':'here_is_the_google_pixel_9_pixel_9_pro_and_pixel_9_pro_fold_pricing_breakdown-news-64111.php',
'g7':'google_pixel_7_and_google_pixel_7_pro_on_sale-news-56144.php',
'p':'oneplus_13_arrives_with_snapdragon_8_elite_updated_cameras_and_6000_mah_battery_-news-65154.php'}
sources['g7']='google_pixel_7_and_pixel_7_pro_on_sale-news-56144.php'
groups=[
('Apple','iPhone 16',2024,'CNY','a16',[(8,128,5999)],'apple_iphone_16-13317.php'),
('Apple','iPhone 13',2021,'MYR','a13',[(4,128,3900)],'apple_iphone_13-11103.php'),
('Samsung','Galaxy S24',2024,'USD','s',[(8,128,800),(8,256,860)],''),
('Samsung','Galaxy S24+',2024,'USD','s',[(12,256,1000),(12,512,1120)],''),
('Samsung','Galaxy S24 Ultra',2024,'USD','s',[(12,256,1300),(12,512,1420),(12,1024,1660)],''),
('Xiaomi','Xiaomi 14',2023,'CNY','x',[(8,256,3999),(12,256,4299),(16,512,4599),(16,1024,4999)],''),
('Xiaomi','Xiaomi 14 Pro',2023,'CNY','x',[(12,256,4999),(16,512,5499),(16,1024,5999)],''),
('Oppo','Find X8 Ultra',2025,'CNY','o',[(12,256,6499),(16,512,6999)],''),
('Oppo','Find X8s+',2025,'CNY','o',[(12,256,4199),(12,512,4699),(16,512,4999)],''),
('Honor','Magic7',2024,'CNY','h',[(12,256,4500),(12,512,4800),(16,512,5000),(16,1024,5500)],''),
('Honor','Magic7 Pro',2024,'CNY','h',[(12,256,5700),(16,512,6200),(16,1024,6700)],''),
('Vivo','X200',2024,'CNY','v',[(12,256,4299),(12,512,4699),(16,512,4999),(16,1024,5499)],''),
('Vivo','X200 Pro',2024,'CNY','v',[(12,256,5299),(16,512,5999),(16,1024,6499)],''),
('Realme','GT7 (China)',2025,'CNY','r',[(12,256,2600),(16,256,2900),(12,512,3000),(16,512,3300),(16,1024,3800)],''),
('Realme','GT 7 Pro Racing Edition',2025,'CNY','rr',[(12,256,3099),(16,256,3399),(12,512,3699),(16,512,3999)],''),
('Huawei','Mate 70',2024,'CNY','m',[(12,256,5499),(12,512,5999),(12,1024,6999)],''),
('Google','Pixel 9',2024,'USD','g',[(12,128,799),(12,256,899)],''),
('Google','Pixel 9 Pro',2024,'USD','g',[(16,128,999),(16,256,1099),(16,512,1219)],''),
('Google','Pixel 7',2022,'USD','g7',[(8,128,599),(8,256,699)],''),
('Google','Pixel 7 Pro',2022,'USD','g7',[(12,128,899),(12,256,999),(12,512,1099)],''),
('One Plus','OnePlus 13',2024,'CNY','p',[(12,256,4499),(16,512,5299),(24,1024,5999)],'')]
extra=[
('Apple','iPhone 7',2016,'USD',2,32,649,'iphone_7_and_iphone_7_plus_go_on_preorder_in_the_us_uk-news-20433.php','apple_iphone_7-review-1497p5.php'),
('Apple','iPhone X',2017,'USD',3,64,999,'iphone_x_iphone_8_and_iphone_8_plus_release_date_and_pricing-news-27233.php','apple_iphone_x-8858.php'),
('Apple','iPhone XR',2018,'USD',3,64,750,'apple_starts_selling_sim_free_iphone_xr_in_the_us-news-34248.php','apple_iphone_xr-9320.php'),
('Apple','iPhone 11',2019,'USD',4,64,699,'iphone_11_11_pro_and_11_pro_max_pricing_roundup-news-39136.php','apple_iphone_11-9848.php'),
('Apple','iPhone SE (2020)',2020,'CNY',3,64,3299,'apples_iphone_se_2020_pricing_and_availability_details-news-42687.php','apple_iphone_se_%282020%29-10170.php'),
('Samsung','Galaxy S23',2023,'USD',8,128,800,'samsung_galaxy_s23_and_s23_announced-news-57403.php',''),
('Samsung','Galaxy S23+',2023,'EUR',8,256,1210,'samsung_galaxy_s23_and_s23_announced-news-57403.php',''),
('Xiaomi','Xiaomi 13',2022,'CNY',8,128,4000,'weekly_poll_xiaomi_13_and_13_pro-news-56873.php',''),
('Xiaomi','Xiaomi 15',2024,'CNY',12,256,4500,'oneplus_13_xiaomi_15_honor_magic7_pro_unveiled_week_44_in_review-news-65176.php',''),
('Xiaomi','Xiaomi 15 Pro',2024,'CNY',12,256,5299,'xiaomi_15_pro_gains_sd_8_elite_5x_periscope_and_beefy_battery_-news-65123.php',''),
('Oppo','Find X8s',2025,'CNY',12,256,4199,'oppo_find_x8s_and_x8s_debut-news-67336.php',''),
('Oppo','Find X8',2024,'CNY',12,256,4199,'oppo_find_x8_and_x8_pro_announced__dimensity_9400_impressive_cameras_-news-65054.php',''),
('Oppo','Find X8 Pro',2024,'CNY',12,256,5299,'oppo_find_x8_and_x8_pro_announced__dimensity_9400_impressive_cameras_-news-65054.php',''),
('Honor','Magic6',2024,'CNY',12,256,4399,'honor_magic6_series_debut_with_snapdragon_8_gen_3_up_to_1tb_storage_and_180mp_periscope-news-61194.php',''),
('Honor','Magic6 Pro',2024,'CNY',16,1024,6699,'honor_magic6_series_debut_with_snapdragon_8_gen_3_up_to_1tb_storage_and_180mp_periscope-news-61194.php',''),
('Honor','Magic7 Lite',2025,'EUR',8,256,370,'honor_launches_the_magic7_pro_and_magic7_lite_in_europe-news-66093.php',''),
('Vivo','X100',2023,'CNY',12,256,3999,'vivo_x100_series_debuts_with_dimensity_9300_x100_pro_brings_100mm_zeiss_apo_periscope-news-60567.php',''),
('Vivo','X100 Pro',2023,'CNY',12,256,4999,'vivo_x100_series_debuts_with_dimensity_9300_x100_pro_brings_100mm_zeiss_apo_periscope-news-60567.php',''),
('Vivo','X200 Pro mini',2024,'CNY',12,256,4699,'vivo_x200_pro_mini_china_price_sale_date-news-65060.php',''),
('Realme','GT6 (China)',2024,'CNY',12,256,2799,'realme_gt6_debuts_in_china-news-63633.php',''),
('Realme','GT 7T',2025,'EUR',12,256,650,'weekly_poll_would_you_buy_the_realme_gt_7_or_the_gt_7t-news-68128.php',''),
('Realme','GT 7 Pro (India)',2024,'INR',12,256,59999,'realme_gt_7_pro_india_price_sale_date-news-65539.php',''),
('Huawei','Mate 70 RS Ultimate',2024,'CNY',16,512,11999,'titaniumclad_huawei_mate_70_pro_and_70_rs_unveiled-news-65491.php',''),
('Huawei','Mate 70 Pro Premium Edition',2025,'CNY',12,256,6199,'huawei_mate_70_pro_gets_a_premium_edition_with_cpu_downgrade-news-66758.php',''),
('Huawei','Pura 70 Pro',2024,'CNY',12,256,6499,'huawei_unveils_pura_70_lineup_on_the_12th_birthday_of_p_series-news-62490.php',''),
('Huawei','Pura 70 Pro+',2024,'CNY',16,512,7999,'huawei_unveils_pura_70_lineup_on_the_12th_birthday_of_p_series-news-62490.php',''),
('Google','Pixel 9 Pro XL',2024,'USD',16,128,1099,'here_is_the_google_pixel_9_pixel_9_pro_and_pixel_9_pro_fold_pricing_breakdown-news-64111.php',''),
('One Plus','OnePlus 12',2023,'CNY',12,256,4299,'oneplus_12_debuts_with_snapdragon_8_gen_3_ip65_rating_and_50w_wireless_charging_-news-60819.php',''),
('One Plus','OnePlus 12R',2024,'USD',8,128,500,'oneplus_12_and_12r_go_on_preorder_in_the_us_amazon_and_best_buy_offer_gift_cards_for_galaxy_s24_phon-news-61355.php',''),
('One Plus','OnePlus 13R',2025,'USD',12,256,599,'oneplus_13r-review-2778p6.php',''),
('One Plus','OnePlus 13T',2025,'CNY',12,256,3399,'oneplus_13t_debuts_with_63_oled_snapdragon_elite_and_6260mah_battery-news-67520.php','')]
for b,m,y,c,r,s,price,source,spec in extra:
 key=f'extra{len(groups)}'
 sources[key]=source
 groups.append((b,m,y,c,key,[(r,s,price)],spec))
rates={'USD':4.0850,'CNY':.6124,'MYR':1,'EUR':4.5190,'INR':.043400}
market={'USD':'United States','CNY':'China','MYR':'Malaysia','EUR':'Europe','INR':'India'}
catalog=[(b,m,y,r,s,c,price,market[c],rates[c],round(price*rates[c],2),base+sources[src],base+spec if spec else '') for b,m,y,c,src,vs,spec in groups for r,s,price in vs]
bybrand=collections.defaultdict(lambda: collections.defaultdict(list))
for v in catalog: bybrand[v[0]][v[1]].append(v)
headers='deviceAge brand model ramCapacity storage internalPerfromanceOverallMark screenDmgScore backDmgScore frameDmgScore msrp actualSoldPrice retentionRatio'.split()
rng=random.Random(42)
def score(v): return round(min(100,max(0,v)),2)
def data():
 for brand,vs in bybrand.items():
  models=list(vs)
  for i in range(50000):
   variants=vs[models[i%len(models)]]
   b,m,y,r,s,c,p,market_,fx,msrp,*_=variants[(i//len(models))%len(variants)]
   age=2026-y
   perf=score(rng.gauss(93-4*age,9))
   wear=rng.betavariate(1.5,4)
   def damage(scale): return score(100*scale*wear*rng.uniform(.3,2)) if rng.random()<.25+wear else 0
   screen,back,frame=damage(1.15),damage(1),damage(.9)
   time=.94*math.exp(-.19*age)
   factor=time*(.55+.45*perf/100)*(1-.45*screen/100-.27*back/100-.18*frame/100)*rng.uniform(.95,1.05)
   price=round(msrp*min(.99,max(.02,factor)),2)
   assert 0<price<msrp and 0<=age<=10
   yield age,b,m,r,s,perf,screen,back,frame,msrp,price,round(price/msrp,10)
method=[
 ('Purpose','500,000 simulated resale scenarios using sourced launch specifications and variant-specific launch prices.'),
 ('Coverage',f'{len(groups)} phone models, {len(catalog)} variants, 10 brands, 50,000 rows each. Variants repeat with different simulated conditions.'),
 ('Age','2026 minus GSMArena release year. Ages 1 through 10 occur across the catalog, with releases from 2016 through 2025.'),
 ('Price basis','Launch-market list prices as reported by GSMArena, converted to MYR. They do not all represent Malaysian MSRP.'),
 ('FX source','https://financialmarkets.bnm.gov.my/data-download-exchange-rates?date_range=year_date&quotation=myr&rate_type=middle_data'),
 ('FX snapshot','13 Nov 2026 BNM middle rates, MYR per unit: CNY 0.6124, USD 4.0850, EUR 4.5190, INR 0.043400. BNM quotes INR per 100.'),
 ('Performance','Simulated internal condition score (higher is better), sampled around 93 minus 4 times age.'),
 ('Damage','Simulated 0–100 severity scores, where 0 is undamaged. No damage depth or screen damage flag.'),
 ('Age factor','0.94 multiplied by exp(-0.19 × age).'),
 ('Condition factors','Internal factor 0.55 + 0.45 × performance/100. External factor 1 − (0.45 × screen + 0.27 × back + 0.18 × frame)/100.'),
 ('Estimated resale','MSRP × age factor × internal factor × external factor × random market factor (0.95–1.05). Retention bounded to 0.02–0.99 before cent rounding.'),
 ('Retention','Rounded simulated resale price divided by the converted launch price.'),
 ('Field names','msrp and actualSoldPrice are MYR. actualSoldPrice is generated, and is not a recorded transaction.'),
 ('Training','Exclude both label columns from inputs. Split by phone model and evaluate on real sales before assessing market accuracy.'),
 ('Scope','Selected GSMArena launch variants, with some prices rounded in source reporting. This is not a complete catalog.')]
def xml_row(i, values, formula=False):
 cells=[]
 for col,v in enumerate(values):
  ref=f'{chr(65+col)}{i}'
  if formula and col==11 and i>1: cells.append(f'<c r="{ref}"><f>K{i}/J{i}</f><v>{v}</v></c>')
  elif isinstance(v,str): cells.append(f'<c r="{ref}" t="inlineStr"><is><t>{escape(v)}</t></is></c>')
  else: cells.append(f'<c r="{ref}"><v>{v}</v></c>')
 return ('<row r="%d">'%i+''.join(cells)+'</row>').encode()
ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
with zipfile.ZipFile('.gsm_build/template.xlsx') as template, zipfile.ZipFile('GSMArena Training Dataset v2.xlsx','w',zipfile.ZIP_DEFLATED,compresslevel=3) as out,open('GSMArena Training Dataset v2.csv','w',newline='',encoding='utf-8') as cf:
 for name in template.namelist():
  if name not in {f'xl/worksheets/sheet{i}.xml' for i in (1,2,3)}: out.writestr(name,template.read(name))
 catalog_header=['Brand','Model','Launch year','RAM GB','Storage GB','Currency','Launch price','Launch market','MYR per unit','Converted MSRP MYR','GSMArena launch source','GSMArena specs source']
 writer=csv.writer(cf);writer.writerow(headers)
 for idx,head,rows,widths,nrows in [(1,headers,data(),[13,13,27,15,12,38,18,17,18,13,19,17],500001),(2,catalog_header,catalog,[13,28,14,12,14,12,15,19,14,25,95,66],len(catalog)+1),(3,['Field','Basis'],method,[25,125],len(method)+1)]:
  with out.open(f'xl/worksheets/sheet{idx}.xml','w') as dest:
   cols=''.join(f'<col min="{j}" max="{j}" width="{w}" customWidth="1"/>' for j,w in enumerate(widths,1))
   end=f'{chr(64+len(head))}{nrows}'
   dest.write(f'<worksheet xmlns="{ns}"><dimension ref="A1:{end}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>{cols}</cols><sheetData>'.encode())
   dest.write(xml_row(1,head))
   for i,row in enumerate(rows,2):
    dest.write(xml_row(i,row,idx==1))
    if idx==1: writer.writerow(row)
   assert i==nrows
   dest.write(f'</sheetData><autoFilter ref="A1:{end}"/></worksheet>'.encode())
print(len(groups),len(catalog),len(bybrand))

