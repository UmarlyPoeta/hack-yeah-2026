import localUnitTest from './LocalUnit.test';
import poiRepositoryTest from './data/PoiRepository.test';
import segmentServiceTest from './data/SegmentService.test';

export default function testsuite() {
  localUnitTest();
  poiRepositoryTest();
  segmentServiceTest();
}
