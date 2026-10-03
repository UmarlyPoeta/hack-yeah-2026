import localUnitTest from './LocalUnit.test';
import geoTest from './Geo.test';
import fixtureParserTest from './FixtureParser.test';
import motionTrackerTest from './MotionTracker.test';
import itineraryTest from './Itinerary.test';

export default function testsuite() {
  localUnitTest();
  geoTest();
  fixtureParserTest();
  motionTrackerTest();
  itineraryTest();
}
