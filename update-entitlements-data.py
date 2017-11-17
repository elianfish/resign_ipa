#!/usr/bin/env python
# -*- coding: utf-8 -*-

import plistlib
import urllib2
import sys
import types


def main():
    src_plist_path = sys.argv[1]
    dst_plist_path = sys.argv[2]
    src_plist = plistlib.readPlist(src_plist_path)
    dst_plist = plistlib.readPlist(dst_plist_path)

    inject_data = src_plist.get('com.apple.developer.associated-domains')
    if inject_data is None:
        _message('Nothing to inejct')
        return

    if 'com.apple.developer.associated-domains' in dst_plist:
        # key已经存在，合并数据
        to_inject = []
        for inject_item in inject_data:
            if inject_item not in dst_plist['com.apple.developer.associated-domains']:
                to_inject.append(inject_item)

        if len(to_inject) == 0:
            # 不需要注入，直接返回
            return

        if type(dst_plist['com.apple.developer.associated-domains']) is types.StringType:
            dst_plist['com.apple.developer.associated-domains'] = inject_data
        else:
            dst_plist['com.apple.developer.associated-domains'] += to_inject

        plistlib.writePlist(dst_plist, dst_plist_path)

def _message(content):
    print('[update entitlements data] %s' % content)


if __name__ == '__main__':
    main()
