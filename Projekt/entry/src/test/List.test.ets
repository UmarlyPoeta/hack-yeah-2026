import localUnitTest from './LocalUnit.test';
import poiRepositoryTest from './data/PoiRepository.test';
import segmentServiceTest from './data/SegmentService.test';
import geoTest from './Geo.test';
import fixtureParserTest from './FixtureParser.test';
import motionTrackerTest from './MotionTracker.test';
import itineraryTest from './Itinerary.test';
import templatesTest from './Templates.test';
import guideTest from './Guide.test';
import walkControllerTest from './WalkController.test';

export default function testsuite() {
  localUnitTest();
  poiRepositoryTest();
  segmentServiceTest();
  geoTest();
  fixtureParserTest();
  motionTrackerTest();
  itineraryTest();
  templatesTest();
  guideTest();
  walkControllerTest();
}
