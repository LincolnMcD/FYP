import json
from pathlib import Path
import tempfile
import unittest
import cv2
import numpy as np

from detection_evaluation.demo import create_demo
from detection_evaluation.inspection import run
from detection_evaluation.geometry import merge_overlapping,register_points,measured,calibration
from detection_evaluation.phone_specs import parse_api_detail,lookup


class InspectionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()

    def test_end_to_end_deduplicates_and_preserves_evidence(self):
        source=create_demo(self.root/'input');result=run(source,self.root/'report')
        self.assertEqual(len(result['observations']),3)
        self.assertEqual(result['unique_defect_count'],2)
        crack=next(d for d in result['unique_defects'] if d['class_name']=='Screen_Crack')
        self.assertEqual(crack['source_image_ids'],['screen_a','screen_b'])
        self.assertEqual(crack['measurement_method'],'primary_observation')
        self.assertEqual(crack['measurement']['area_pixels'],
            next(o for o in result['observations'] if o['id']==crack['primary_observation_id'])['features']['measurement']['area_pixels'])
        self.assertIsNone(crack['appearance']['physical_depth'])
        self.assertTrue((self.root/'report/report.html').exists())
        self.assertTrue((self.root/'report/unique_defects.csv').exists())
        self.assertEqual(len(result['images'][0]['raw_predictions']),2)
        self.assertEqual((self.root/'report/screen_a/original.png').read_bytes(),(self.root/'input/screen_a.png').read_bytes())
        for surface in result['summary']['surfaces']:
            self.assertTrue(0<=surface['visible_region_coverage']<=1)
        self.assertTrue(result['grade_requires_review']) # No frame photos.

    def test_uncertain_matching_stays_separate(self):
        source=create_demo(self.root/'input');cfg=json.loads(source.read_text())
        cfg['matching']['correspondences']={};source.write_text(json.dumps(cfg))
        result=run(source,self.root/'report')
        self.assertEqual(result['unique_defect_count'],3)
        self.assertTrue(any(r['reason']=='insufficient_correspondences' for r in result['review_items']))
        screen=next(s for s in result['summary']['surfaces'] if s['surface_id']=='Screen')
        self.assertFalse(screen['complete'])
        self.assertIsNone(result['summary']['classes']['Screen_Crack']['total_area_cm2'])

    def test_same_class_overlap_transitive_union_no_cross_class_merge(self):
        def item(i,mask,name='Screen_Crack'):
            return {'id':str(i),'class_name':name,'surface_id':'Screen','mask':mask,'confidence':.8}
        a=np.zeros((30,30),bool);b=a.copy();c=a.copy()
        a[2:10,2:10]=1;b[8:16,8:16]=1;c[14:20,14:20]=1
        rows=merge_overlapping([item(1,a),item(2,c),item(3,b),item(4,a,'Screen_Scratch')])
        self.assertEqual(len(rows),2)
        self.assertEqual(next(r for r in rows if r['class_name']=='Screen_Crack')['mask'].sum(),(a|b|c).sum())

    def test_bad_geometry_rejected(self):
        mask=np.ones((200,200),bool)
        line=np.float32([[i*5,50] for i in range(20)])
        self.assertFalse(register_points(line,line,mask,mask)['reliable'])
        points=np.float32([[x,y] for y in (30,70,110,150) for x in (30,70,110,150)])
        mirrored=points.copy();mirrored[:,0]=199-mirrored[:,0]
        self.assertFalse(register_points(points,mirrored,mask,mask)['reliable'])
        self.assertTrue(register_points(points,points+[3,2],mask,mask)['reliable'])

    def test_area_requires_calibration_and_coverage_never_exceeds_one(self):
        part=np.ones((100,100),bool);mask=part.copy()
        self.assertIsNone(measured(mask,part)['area_cm2'])
        self.assertEqual(measured(mask,part)['coverage'],1)
        metric=calibration({'planar':True,'calibration':{'reviewed':True,'image_points':[[0,0],[99,0],[99,99],[0,99]],'pixels_per_mm':2}},
                           {'width_mm':10,'height_mm':20,'source':'test fixture'})
        self.assertAlmostEqual(measured(mask,part,metric)['area_cm2'],2,delta=.001)

    def test_brand_model_lookup_and_nominal_area_not_exact(self):
        profile=lookup('Apple','iPhone 15')
        self.assertAlmostEqual(profile['body_dimensions_mm']['width'],71.6)
        self.assertFalse(profile['exact_part_areas_available'])
        with self.assertRaises(ValueError):lookup('Missing','Unknown')
        with self.assertRaises(ValueError):lookup('Samsung','Apple iPhone 15')
        payload={'data':{'specifications':[
            {'title':'Body','specs':[{'key':'Dimensions','val':['150 x 70 x 8 mm']}]},
            {'title':'Display','specs':[{'key':'Size','val':['6.1 inches']},{'key':'Resolution','val':['1080 x 2400 pixels']}]}]}}
        profile=parse_api_detail('Brand','Model',payload,'https://example.test/spec')
        self.assertAlmostEqual(profile['nominal_areas_cm2']['Back'],105)
        self.assertFalse(profile['exact_part_areas_available'])

    def test_complementary_union_and_no_area_sum(self):
        source=create_demo(self.root/'input');cfg=json.loads(source.read_text())
        # Force uncertainty about completeness, allowing reliable registered union.
        for image in cfg['images'][:2]:
            for row in image['predictions']:row['complete']=False
        from PIL import Image
        a=np.asarray(Image.open(self.root/'input/crack_a2.png')).copy();a[220:]=0
        Image.fromarray(a).save(self.root/'input/crack_a2.png')
        b=np.asarray(Image.open(self.root/'input/crack_b.png')).copy();b[:115]=0
        Image.fromarray(b).save(self.root/'input/crack_b.png')
        source.write_text(json.dumps(cfg));result=run(source,self.root/'report')
        crack=next(d for d in result['unique_defects'] if d['class_name']=='Screen_Crack')
        self.assertEqual(crack['measurement_method'],'registered_binary_union')
        sizes=[o['features']['measurement']['area_cm2'] for o in result['observations'] if o['class_name']=='Screen_Crack']
        self.assertLess(crack['measurement']['area_cm2'],sum(sizes))
        self.assertGreater(crack['measurement']['area_cm2'],max(sizes))

    def test_different_devices_rejected(self):
        source=create_demo(self.root/'input');cfg=json.loads(source.read_text())
        cfg['images'][0]['device_id']='phone_a';cfg['images'][1]['device_id']='phone_b'
        source.write_text(json.dumps(cfg))
        with self.assertRaises(ValueError):run(source,self.root/'report')

    def test_cross_class_same_registered_location_requires_review(self):
        source=create_demo(self.root/'input');cfg=json.loads(source.read_text())
        cfg['images'][1]['predictions'][0]['class_name']='Screen_Scratch'
        source.write_text(json.dumps(cfg));report=run(source,self.root/'report')
        self.assertEqual(report['unique_defect_count'],3)
        self.assertTrue(any(r['reason']=='conflicting_classes_at_same_registered_location' for r in report['review_items']))

    def test_nominal_outline_calibration_is_marked_approximate(self):
        from detection_evaluation.geometry import estimate_calibration
        mask=np.zeros((120,80),bool);mask[10:110,10:70]=1
        profile={'width_mm':60,'height_mm':100,'source':'nominal device dimensions','dimension_status':'nominal_rectangle_estimate'}
        estimate=estimate_calibration(mask,profile)
        metric=calibration({'planar':True,'calibration':estimate},profile)
        result=measured(mask,mask,metric)
        self.assertEqual(result['area_accuracy'],'approximate_nominal_geometry')


if __name__=='__main__':unittest.main()
