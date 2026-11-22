// zig-geos smoke test (C++ API, links libc++): a polygon from WKT through
// geos::geom::GeometryFactory, its area and a buffer's area, prints OK.
// GEOS headers warn on C++ API use unless this is defined.
#define USE_UNSTABLE_GEOS_CPP_API
#include <cmath>
#include <iostream>
#include <memory>

#include <geos/geom/Geometry.h>
#include <geos/geom/GeometryFactory.h>
#include <geos/io/WKTReader.h>
#include <geos/version.h>

int main() {
    auto factory = geos::geom::GeometryFactory::create();
    geos::io::WKTReader reader(*factory);
    std::unique_ptr<geos::geom::Geometry> sq = reader.read("POLYGON ((0 0, 2 0, 2 2, 0 2, 0 0))");
    std::unique_ptr<geos::geom::Point> pt = factory->createPoint(geos::geom::CoordinateXY(0, 0));
    std::unique_ptr<geos::geom::Geometry> buf = pt->buffer(1.0, 64);
    std::cout << "GEOS " << GEOS_VERSION << " C++: square area " << sq->getArea()
              << ", buffer area " << buf->getArea() << std::endl;
    if (sq->getArea() != 4.0 || std::fabs(buf->getArea() - 3.14159265358979) > 1e-3) {
        std::cout << "FAIL: unexpected area" << std::endl;
        return 1;
    }
    std::cout << "OK" << std::endl;
    return 0;
}
