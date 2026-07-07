int mapVisualToRawOffset(String visual, String raw, int visualOffset) {
  int vIndex = 0;
  int rIndex = 0;

  while (vIndex < visualOffset && rIndex < raw.length) {
    if (vIndex < visual.length && visual[vIndex] == '\uFFFC') {
      if (raw[rIndex] == '!') {
        int closeParen = raw.indexOf(')', rIndex);
        if (closeParen != -1) {
          rIndex = closeParen + 1;
          vIndex++;
          continue;
        }
      }
    }

    if (vIndex < visual.length && visual[vIndex] == raw[rIndex]) {
      vIndex++;
      rIndex++;
    } else {
      rIndex++;
    }
  }

  if (visualOffset == visual.length) {
    while (rIndex < raw.length) {
      if (vIndex < visual.length) {
        if (visual[vIndex] == '\uFFFC') break;
        if (visual[vIndex] == raw[rIndex]) break;
      }
      rIndex++;
    }
  }

  return rIndex;
}

int mapRawToVisualOffset(String visual, String raw, int rawOffset) {
  int vIndex = 0;
  int rIndex = 0;

  while (rIndex < rawOffset && vIndex < visual.length) {
    if (vIndex < visual.length && visual[vIndex] == '\uFFFC') {
      if (rIndex < raw.length && raw[rIndex] == '!') {
        int closeParen = raw.indexOf(')', rIndex);
        if (closeParen != -1) {
          if (rawOffset <= closeParen) return vIndex;
          rIndex = closeParen + 1;
          vIndex++;
          continue;
        }
      }
    }

    if (rIndex < raw.length && visual[vIndex] == raw[rIndex]) {
      vIndex++;
      rIndex++;
    } else {
      rIndex++;
    }
  }
  return vIndex;
}
