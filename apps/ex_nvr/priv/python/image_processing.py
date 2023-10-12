import cv2
import numpy as np
import base64

pfov = 100
fov = 180
dtype = "orthographic"


def _map(i, j, ofocinv, dim, x_center, y_center):
    xd = i - x_center - 1
    yd = j - y_center - 1

    rd = np.hypot(xd, yd)
    phiang = np.arctan(ofocinv * rd)

    if dtype == "linear":
        ifoc = dim * 180 / (fov * np.pi)
        rr = ifoc * phiang
        # rr = "rr={}*phiang;".format(ifoc)

    elif dtype == "equalarea":
        ifoc = dim / (2.0 * np.sin(fov * np.pi / 720))
        rr = ifoc * np.sin(phiang / 2)
        # rr = "rr={}*sin(phiang/2);".format(ifoc)

    elif dtype == "orthographic":
        ifoc = dim / (2.0 * np.sin(fov * np.pi / 360))
        rr = ifoc * np.sin(phiang)
        # rr="rr={}*sin(phiang);".format(ifoc)

    elif dtype == "stereographic":
        ifoc = dim / (2.0 * np.tan(fov * np.pi / 720))
        rr = ifoc * np.tan(phiang / 2)

    rdmask = rd != 0

    xs = xd.copy()
    ys = yd.copy()

    xs[rdmask] = (rr[rdmask] / rd[rdmask]) * xd[rdmask] + x_center
    ys[rdmask] = (rr[rdmask] / rd[rdmask]) * yd[rdmask] + y_center

    xs[~rdmask] = 0
    ys[~rdmask] = 0

    xs = xs.astype(int)
    ys = ys.astype(int)
    return xs, ys


def get_with_defaults(a, xx, yy, nodata):
    res = a[np.clip(yy, 0, a.shape[0] - 1), np.clip(xx, 0, a.shape[1] - 1)]

    myy = np.ma.masked_outside(yy, 0, a.shape[0] - 1).mask
    mxx = np.ma.masked_outside(xx, 0, a.shape[1] - 1).mask

    np.choose(myy + mxx, [res, nodata], out=res)
    return res


def from_base64(img_str):
    im_bytes = base64.b64decode(str(img_str, 'utf-8'))
    im_arr = np.frombuffer(im_bytes, dtype=np.uint8)
    return cv2.imdecode(im_arr, flags=cv2.IMREAD_COLOR)


def undistort_image(image_base64):
    distorted_img = from_base64(image_base64)

    height, width, _ = distorted_img.shape
    x_center = width // 2
    y_center = height // 2

    dim = np.sqrt(width ** 2.0 + height ** 2.0)
    ofoc = dim / (2 * np.tan(pfov * np.pi / 360))
    ofocinv = 1.0 / ofoc

    i = np.arange(width)
    j = np.arange(height)
    i, j = np.meshgrid(i, j)

    xs, ys, = _map(i, j, ofocinv, dim, x_center, y_center)

    distorted_img[j, i, :] = distorted_img[
        np.clip(ys, 0, height - 1),
        np.clip(xs, 0, width - 1),
        :
    ]

    return base64.b64encode(cv2.imencode(".png", distorted_img)[1])
