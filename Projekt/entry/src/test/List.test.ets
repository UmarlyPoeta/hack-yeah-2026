import localUnitTest from './LocalUnit.test';
import geoTest from './Geo.test';
import fixtureParserTest from './FixtureParser.test';

export default function testsuite() {
  localUnitTest();
  geoTest();
  fixtureParserTest();
}
