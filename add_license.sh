for PACK in `ls -d */`; do
  echo "Processing pack $PACK... "

  if [ -f "${PACK}/LICENSE" ]; then
      echo "Passing ${PACK} already has a license"
      continue
  fi

  cd ${PACK}
  cp -f ../LICENSE .
  git add LICENSE
  git commit -m "Add missing LICENSE file."
  git push origin master
  cd ../
done
