{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoMonomorphismRestriction  #-}
{-# LANGUAGE TemplateHaskell #-}
module Shakebook.Defaults where

import           Control.Comonad
import           Control.Comonad.Cofree
import           Control.Comonad.Store.Class
import           Control.Comonad.Store.Zipper
import           Control.Monad.Extra
import           Data.Aeson                   as A
import           Data.List.Split
import           Data.Text.Time
import           Development.Shake hiding (readFile')
import qualified Development.Shake.FilePath   as S
import           RIO
import qualified RIO.ByteString.Lazy          as LBS
import           RIO.List
import           RIO.List.Partial
import qualified RIO.Map                      as M
import           RIO.Partial
import qualified RIO.Text                     as T
import           RIO.Time
import           Path                         as P
import           Shakebook.Aeson
import           Shakebook.Conventions
import           Shakebook.Shake
import           Shakebook.Data
import           Shakebook.Within
import           Text.DocTemplates
import           Text.Pandoc.Class
import           Text.Pandoc.Definition
import           Text.Pandoc.Options
import           Text.Pandoc.PDF
import           Text.Pandoc.Readers
import           Text.Pandoc.Templates
import           Text.Pandoc.Walk
import           Text.Pandoc.Writers

defaultMonthUrlFormat :: UTCTime -> String
defaultMonthUrlFormat = formatTime defaultTimeLocale "%Y-%m"

defaultPrettyMonthFormat :: UTCTime -> String
defaultPrettyMonthFormat = formatTime defaultTimeLocale "%B, %Y"

defaultPrettyTimeFormat :: UTCTime -> String
defaultPrettyTimeFormat = formatTime defaultTimeLocale "%A, %B %d, %Y"

defaultIndexFileFragment :: Path Rel File
defaultIndexFileFragment = $(mkRelFile "index.html")

defaultMonthDirFragment :: MonadThrow m => UTCTime -> m (Path Rel Dir)
defaultMonthDirFragment t = do
  k <- parseRelDir $ defaultMonthUrlFormat t
  return $ $(mkRelDir "posts/months") </> k

defaultMonthUrlFragment :: UTCTime -> Text
defaultMonthUrlFragment t = T.pack $ "/posts/months/" <> defaultMonthUrlFormat t

defaultEnrichPost :: Value -> Value
defaultEnrichPost = enrichTeaser "<!--more-->"
                  . enrichTagLinks ("/posts/tags/" <>)
                  . enrichPrettyDate defaultPrettyTimeFormat
--                  . enrichTypicalUrl

defaultMarkdownReaderOptions :: ReaderOptions
defaultMarkdownReaderOptions = def { readerExtensions = pandocExtensions }

defaultHtml5WriterOptions :: WriterOptions
defaultHtml5WriterOptions = def { writerHTMLMathMethod = MathJax ""}

defaultLatexWriterOptions :: WriterOptions
defaultLatexWriterOptions = def { writerTableOfContents = True
                         , writerVariables = Context $ M.fromList [
                                               ("geometry", SimpleVal "margin=3cm")
                                             , ("fontsize", SimpleVal "10")
                                             , ("linkcolor",SimpleVal "blue")]
                         }

defaultSbSrcDir :: Path Rel Dir
defaultSbSrcDir = $(mkRelDir "site")

defaultSbOutDir :: Path Rel Dir
defaultSbOutDir = $(mkRelDir "public")

defaultPostsPerPage :: Int
defaultPostsPerPage = 5

defaultSbConfig :: Text -- ^ BaseURL
                -> SbConfig
defaultSbConfig x = SbConfig defaultSbSrcDir defaultSbOutDir x defaultMarkdownReaderOptions defaultHtml5WriterOptions defaultPostsPerPage

withHtmlExtension :: MonadThrow m => Path Rel File -> m (Path Rel File)
withHtmlExtension = replaceExtension ".html"

withMarkdownExtension :: MonadThrow m => Path Rel File -> m (Path Rel File)
withMarkdownExtension = replaceExtension ".md"

affixBlogNavbar :: MonadShakebookAction r m
                => [FilePattern]
                -> Text
                 -> Text
                -> (UTCTime -> Text)
                -> (UTCTime -> Text)
                -> (Value -> Value) -- ^ Post enrichment.
                -> Value -> m Value
affixBlogNavbar patterns a b c d e x = do
  xs <- loadSortEnrich patterns (Down . viewPostTime) e
  return $ withJSON (genBlogNavbarData a b c d (snd <$> xs)) $ x

affixRecentPosts :: MonadShakebookAction r m
                 => [FilePattern]
                 -> Int
                 -> (Value -> Value) -- ^ Post enrichment
                 -> Value -> m Value
affixRecentPosts patterns n e x = do
  xs <- loadSortEnrich patterns (Down . viewPostTime) e
  return $ withRecentPosts (take n (snd <$> xs)) $ x



defaultDocsPatterns :: MonadShakebookRules r m
                    => Cofree [] FilePath -- Rosetree Table of Contents.
                    -> FilePath
                    -> (Value -> Value) -- Extra data modifiers.
                    -> m ()
defaultDocsPatterns toc tmpl withData = ask >>= \r -> view sbConfigL >>= \SbConfig{..} -> do
--  let e = enrichTypicalUrl
  tmpl' <- parseRelFile tmpl
  toc' <- mapM (parseRelFile >=> (`asWithin` sbOutDir)  >=> mapWithinT withHtmlExtension) toc
  liftRules $ void . sequence . flip extend toc' $ \xs -> (toFilePath . fromWithin $ extract xs) %>
         \out -> runShakebookA r $ do
             out' <- ((`asWithin` sbOutDir) <=< parseRelFile) out
             ys <- mapM (blinkAndMapT sbSrcDir withMarkdownExtension >=> readMarkdownFile') toc'
             zs <- mapM (blinkAndMapT sbSrcDir withMarkdownExtension >=> readMarkdownFile') xs
             v  <- (readMarkdownFile' <=< blinkAndMapT sbSrcDir withMarkdownExtension) out'
             let v' = withData . withJSON (genTocNavbarData ys) . withSubsections (lower (zs)) $ v
             liftAction $ buildPageAction tmpl' v' (fromWithin out')

defaultPostIndexData :: MonadShakebookAction r m
                     => [FilePattern]
                     -> (a -> Value -> Bool) -- ^ A filtering function 
                     -> (a -> Text) -- ^ How to turn the id into a Title.
                     -> (a -> Text -> Text) -- ^ How to turn the id and a page number (as Text) into a URL link.
                     -> a -- ^ The id itself.
                     -> m (Zipper [] Value) -- A pager of index pages.
defaultPostIndexData pat f t l a = view sbConfigL >>= \SbConfig {..} -> do
  xs <- loadSortFilterEnrich pat (Down . viewPostTime) (f a) defaultEnrichPost
  let ys = genIndexPageData (snd <$> xs) (t a) (l a) sbPPP
  return $ fromJust $ ys

defaultPagerPattern :: MonadShakebookRules r m
                    => FilePattern
                    -> FilePath
                    -> (FilePattern -> Int) -- ^ How to extract a page number from the Filepattern.
                    -> (FilePattern -> a) -- ^ How to extract an id from the FilePattern
                    -> (a -> ShakebookA r (Zipper [] Value))
                    -> (Zipper [] Value -> ShakebookA r (Zipper [] Value))
                    -> m ()
defaultPagerPattern fp tmpl f g h w = ask >>= \r -> view sbConfigL >>= \SbConfig{..} -> do
  tmpl' <- parseRelFile tmpl
  liftRules $ (toFilePath sbOutDir S.</> fp) %> \x -> runShakebookA r $ do
                              x' <- ((`asWithin` sbOutDir) <=< parseRelFile) x
                              let x'' = toFilePath $ whatLiesWithin x'
                              xs <- (w <=< h) $ g (x'')
                              let b = extract (seek (f x'') xs)
                              liftAction $ buildPageAction tmpl' b (fromWithin x')

defaultPostIndexPatterns :: MonadShakebookRules r m
                         => [FilePattern]
                         -> FilePath
                         -> (Zipper [] Value -> ShakebookA r (Zipper [] Value)) -- ^ Pager extension.
                         -> m ()
defaultPostIndexPatterns pat tmpl extData = do
   defaultPagerPattern "posts/index.html" tmpl
                       (const 0)
                       (const ())
                       (defaultPostIndexData pat (const $ (const True))
                                                 (const "Posts")
                                                 (const ("/posts/pages/" <>)))
                       extData
   defaultPagerPattern ("posts/pages/*/index.html") tmpl
                       ((+ (-1)) . read . (!! 2) . splitOn "/")
                       (const ())
                       (defaultPostIndexData pat (const $ (const True))
                                                 (const "Posts")
                                                 (const ("/posts/pages/" <>)))
                       extData

defaultTagIndexPatterns :: MonadShakebookRules r m
                         => [FilePattern]
                        -> FilePath
                        -> (Zipper [] Value -> ShakebookA r (Zipper [] Value)) -- ^ Pager extension.
                        -> m ()
defaultTagIndexPatterns pat tmpl extData = do
 defaultPagerPattern ("posts/tags/*/index.html") tmpl
                     (const 0)
                     (T.pack . (!! 2) . splitOn "/")
                     (defaultPostIndexData pat (\x y -> elem x (viewTags y) )
                                               ("Posts tagged " <>)
                                               (\x y -> ("/posts/tags/" <> x <> "/pages/" <> y)))
                     extData
 defaultPagerPattern ("posts/tags/*/pages/*/index.html") tmpl
                     ((+ (-1)) . read . (!! 4) . splitOn "/")
                     (T.pack . (!! 2) . splitOn "/")
                     (defaultPostIndexData pat (\x y -> elem x (viewTags y))
                                               ("Posts tagged " <>)
                                               (\x y -> ("/posts/tags/" <> x <> "/pages/" <> y)))
                     extData

defaultMonthIndexPatterns :: MonadShakebookRules r m
                          => [FilePattern]
                          -> FilePath
                          -> (Zipper [] Value -> ShakebookA r (Zipper [] Value)) -- ^ Pager extension.
                          -> m ()
defaultMonthIndexPatterns pat tmpl extData = do
 defaultPagerPattern "posts/months/*/index.html" tmpl
                     (const 0)
                     (parseISODateTime . T.pack . (!! 2) . splitOn "/")
                     (defaultPostIndexData pat
                        (\x y -> sameMonth x (viewPostTime y))
                        (("Posts from " <>) . T.pack . defaultPrettyMonthFormat)
                        (\x y -> ("/posts/months/" <> T.pack (defaultMonthUrlFormat x) <> "/pages" <> y)))
                     extData
 defaultPagerPattern "posts/months/*/pages/*/index.html" tmpl
                      ((+ (-1)) . read . (!! 4) . splitOn "/")
                      (parseISODateTime . T.pack . (!! 2) . splitOn "/")
                       (defaultPostIndexData pat
                           (\x y -> sameMonth x (viewPostTime y))
                           (("Posts from " <>) . T.pack . defaultPrettyMonthFormat)
                           (\x y -> ("/posts/months/" <> T.pack (defaultMonthUrlFormat x) <> "/pages" <> y)))
                       extData

{-|
   Default Posts Pager. 
-}
defaultPostsPatterns :: MonadShakebookRules r m
                     => FilePattern
                     -> FilePath
                     -> (Value -> ShakebookA r Value) -- ^ A post loader function.
                     -> (Zipper [] Value -> ShakebookA r (Zipper [] Value)) -- ^ A transformation on the entire post zipper.
                     -> m ()
defaultPostsPatterns pat tmpl e extData = ask >>= \r -> view sbConfigL >>= \SbConfig {..} ->
  liftRules $ toFilePath sbOutDir S.</> pat %> \out -> runShakebookA r $ do
    out'  <- ((`asWithin` sbOutDir) <=< parseRelFile) out
    tmpl' <- parseRelFile tmpl
    xs    <- loadSortEnrich [pat] (Down . viewPostTime) defaultEnrichPost
    sortedPosts <- mapM (\(s,x) -> e x >>= \e' -> return (s, e')) xs
    i <- mapWithinT withMarkdownExtension out'
    let k = fromJust $ elemIndex i (fst <$> sortedPosts)
    let z = fromJust $ seek k <$> zipper (snd <$> sortedPosts)
    z' <- extData z
    liftAction $ buildPageAction tmpl' (extract z') (fromWithin out')

makePDFLaTeX :: Pandoc -> PandocIO (Either LBS.ByteString LBS.ByteString)
makePDFLaTeX p = do
  t <- compileDefaultTemplate "latex"
  makePDF "pdflatex" [] writeLaTeX defaultLatexWriterOptions { writerTemplate = Just t } p

handleImages :: (Text -> Text) -> Inline -> Inline
handleImages f (Image attr ins (src,txt)) =
  if T.takeEnd 4 src == ".mp4" then Str (f src)
  else Image attr ins ("public/" <> src, txt)
handleImages _ x = x

handleHeaders :: Int -> Block -> Block
handleHeaders i (Header a as xs) = Header (max 1 (a + i)) as xs
handleHeaders _ x                = x

pushHeaders :: Int -> Cofree [] Pandoc -> Cofree [] Pandoc
pushHeaders i (x :< xs) = walk (handleHeaders i) x :< map (pushHeaders (i+1)) xs

-- | Build a PDF from a Cofree table of contents.
buildPDF :: MonadShakebookAction r m => Cofree [] (Path Rel File) -> Path Rel File -> FilePath -> m ()
buildPDF toc meta out = view sbConfigL >>= \SbConfig {..} -> liftAction $ do
  y <- mapM (readFileIn' sbSrcDir) toc
  m <- readFileIn' sbSrcDir meta
  Right f <- liftIO . runIOorExplode $ do
    k <- mapM (readMarkdown sbMdRead ) y
    a <- readMarkdown sbMdRead $ m
    let z = walk (handleImages (\x -> "[Video available at " <> sbBaseUrl <> x <> "]")) $ foldr (<>) a $ pushHeaders (-1) k
    makePDFLaTeX z
  LBS.writeFile out f

{-|
  Default Single Page Pattern, see tests for usage. It's possible this could just be
  called singlePagePattern, as there's no hardcoded strings here, but it would need to
  run entirely within the monad to translate filepaths.
-}
defaultSinglePagePattern :: MonadShakebookRules r m
                         => FilePath -- ^ The output filename e.g "index.html".
                         -> FilePath -- ^ A tmpl file.
                         -> (Value -> ShakebookA r Value) -- ^ Last minute enrichment.
                         -> m ()
defaultSinglePagePattern out tmpl withDataM = ask >>= \r -> view sbConfigL >>= \SbConfig {..} -> do
  liftRules $ toFilePath sbOutDir S.</> out %> \x -> void $ runShakebookA r $ do 
                 tmpl' <-  parseRelFile tmpl
                 x'    <- parseRelFile x
                 x''   <- (blinkAndMapT sbSrcDir withMarkdownExtension <=< (`asWithin` sbOutDir)) $ x'
                 v     <- withDataM =<< readMarkdownFile' x''
                 liftAction $ buildPageAction tmpl' v x'

{-|
  Default statics patterns. Takes a list of filepatterns and adds a rule that copies everything
  verbatim
-}
defaultStaticsPatterns :: MonadShakebookRules r m => [FilePattern] -> m ()
defaultStaticsPatterns xs = ask >>= \r -> view sbConfigL >>= \SbConfig {..} -> do
  liftRules $ mconcat $ flip map xs $ \x ->
      (toFilePath sbOutDir S.</> x) %> \y -> do
        y' <- liftIO $ ((`asWithin` sbOutDir) <=< parseRelFile) y
        let y'' = blinkWithin sbSrcDir y'
        copyFileChanged' (fromWithin y'') (fromWithin y')

-- | Default "shake clean" phony, cleans your output directory.
defaultCleanPhony :: MonadShakebookRules r m => m ()
defaultCleanPhony = view sbConfigL >>= \SbConfig {..} -> liftRules $
  phony "clean" $ do
      putInfo $ "Cleaning files in " ++ toFilePath sbOutDir
      removeFilesAfter (toFilePath sbOutDir) ["//*"]

defaultSinglePagePhony :: MonadShakebookRules r m => String -> FilePath -> m ()
defaultSinglePagePhony x y = view sbConfigL >>= \SbConfig{..} -> liftRules $
  phony x $ liftIO (parseRelFile y) >>= needPathIn sbSrcDir . pure

{-|
  Default "shake statics" phony rule. automatically runs need on "\<out\>\/thing\/\*" for every
  thing found in "images\/", "css\/", "js\/" and "webfonts\/"
-}
defaultStaticsPhony :: MonadShakebookRules r m => [FilePattern] -> m ()
defaultStaticsPhony pattern = view sbConfigL >>= \SbConfig{..} -> liftRules $ 
  phony "statics" $ 
    getDirectoryFilesWithin' sbSrcDir pattern >>= needWithin

{-|
  Default "shake posts" phony rule. takes a [FilePattern] pointing to the posts and
  and calls need on "\<out\>\/posts\/\<filename\>.html" for each markdown post found.
-}  
defaultPostsPhony :: MonadShakebookRules r m => [FilePattern] -> m ()
defaultPostsPhony pattern = view sbConfigL >>= \SbConfig{..} -> liftRules $
  phony "posts" $ 
    getDirectoryFilesWithin' sbSrcDir pattern >>= liftIO . mapM (mapWithinT withHtmlExtension) >>= needWithin


{-|
  Default "shake posts-index" phony rule. Takes a [FilePattern] of posts to
  discover and calls need on "\<out\>\/posts\/index.html" and
  "\<out\>\/posts\/pages\/\<n\>\/index.html" for each page required.
-}
defaultPostIndexPhony :: MonadShakebookRules r m => [FilePattern] -> m ()
defaultPostIndexPhony pattern = ask >>= \r -> view sbConfigL >>= \SbConfig{..} -> liftRules $
    phony "posts-index" $ do
      fp  <- getDirectoryFilesWithin' sbSrcDir pattern
      fp' <- runShakebookA r $ mapM readMarkdownFile' fp
      needPathIn sbOutDir [dirPosts </> fileIndexHTML]
      ps  <- liftIO $ paginate' sbPPP fp'
      ps' <- liftIO $ defaultPagePaths dirPosts ps
      needPathIn sbOutDir ps'

{-|
  Default "shake tag-index" phony rule. Takes a [FilePattern] of posts to
  discover and calls need on "\<out\>\/posts\/tags\/\<tag\>\/index.html" and
  "\<out\>\/posts\/tags\/\<tag\>\/pages\/\<n\>\/index.html" for each tag discovered and for
  each page required per tag filter.
-}
defaultTagIndexPhony :: MonadShakebookRules r m => [FilePattern] -> m ()
defaultTagIndexPhony pattern = ask >>= \r -> view sbConfigL >>= \SbConfig{..} -> liftRules $
   phony "tag-index" $ do
      fp  <- getDirectoryFilesWithin' sbSrcDir pattern
      fp' <- runShakebookA r $ mapM readMarkdownFile' fp
      let times = viewAllPostTags fp'
      forM_ times $ \t -> do
        u <- liftIO $ parseRelDir $ T.unpack t
        needPathIn sbOutDir [dirPosts </> dirTags </> u </> fileIndexHTML]
        ps  <- liftIO $ paginate' sbPPP (tagFilterPosts t fp')
        ps' <- liftIO $ defaultPagePaths (dirPosts </> dirTags </> u) ps
        needPathIn sbOutDir ps'

defaultPagePaths :: MonadThrow m => Path Rel Dir -> Zipper [] [a] -> m [Path Rel File]
defaultPagePaths a xs = forM [1..size xs] $ parseRelDir . show >=> \p -> return $ a </> dirPages </> p </> fileIndexHTML

fileIndexHTML :: Path Rel File
fileIndexHTML = $(mkRelFile "index.html")

dirPosts :: Path Rel Dir
dirPosts = $(mkRelDir "posts")

dirMonths :: Path Rel Dir
dirMonths = $(mkRelDir "months")

dirPages :: Path Rel Dir
dirPages = $(mkRelDir "pages")

dirTags :: Path Rel Dir
dirTags = $(mkRelDir "tags")

{-|
  Default "shake month-index" phony rule. Takes a [FilePattern] of posts to
  discover and calls need on "\<out\>\/posts\/months\/\<yyyy-md\>\/index.html" and
  "\<out\>\/posts\/months\/\<yyyy-md\>\/pages\/\<n\>\/index.html" for each month
  discovered that contains a post and for each page required per month filter.
-}
defaultMonthIndexPhony :: MonadShakebookRules r m => [FilePattern] -> m ()
defaultMonthIndexPhony pattern = ask >>= \r -> view sbConfigL >>= \SbConfig{..} -> liftRules $
   phony "month-index" $ do
      fp  <- getDirectoryFilesWithin' sbSrcDir pattern
      fp' <- runShakebookA r $ mapM readMarkdownFile' fp
      let times = viewAllPostTimes fp'
      forM_ times $ \t -> do
        u <- liftIO $ parseRelDir $ defaultMonthUrlFormat t
        needPathIn sbOutDir [dirPosts </> dirMonths </> u </> fileIndexHTML]
        ps  <- liftIO $ paginate' sbPPP (monthFilterPosts t fp')
        ps' <- liftIO $ defaultPagePaths (dirPosts </> dirMonths </> u) ps
        needPathIn sbOutDir ps'

-- | Default "shake docs" phony rule, takes a Cofree [] String as a table of contents.
defaultDocsPhony :: MonadShakebookRules r m
                 => Cofree [] String 
                 -> m ()
defaultDocsPhony toc = view sbConfigL >>= \SbConfig{..} -> liftRules $ 
    phony "docs" $ do
      let xs = foldr ((<>) . pure) [] $ toc
      pure xs >>= liftIO . mapM (parseRelFile >=> withHtmlExtension) >>= needPathIn sbOutDir
