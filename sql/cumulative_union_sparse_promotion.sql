-- Setup the table
--

SELECT hll_set_output_version(1);

-- This test relies on a non-standard fixed sparse-to-compressed
-- threshold value.
--
SELECT hll_set_max_sparse(512);

DROP TABLE IF EXISTS test_bsnvqefe;

CREATE TABLE test_bsnvqefe (
    recno                       SERIAL,
    cardinality                 double precision,
    compressed_multiset         hll,
    union_cardinality           double precision,
    union_compressed_multiset   hll
);

-- Copy the CSV data into the table
--
\copy test_bsnvqefe (cardinality,compressed_multiset,union_cardinality,union_compressed_multiset) from sql/data/cumulative_union_sparse_promotion.csv with csv header

SELECT COUNT(*) FROM test_bsnvqefe;

-- Cardinality of incremental multisets
--
SELECT recno,
       cardinality,
       hll_cardinality(compressed_multiset)
  FROM test_bsnvqefe
 WHERE cardinality != hll_cardinality(compressed_multiset)
 ORDER BY recno;

-- Cardinality of unioned multisets
--
SELECT recno,
       union_cardinality,
       hll_cardinality(union_compressed_multiset)
  FROM test_bsnvqefe
 WHERE round(union_cardinality::numeric, 10) !=
       round(hll_cardinality(union_compressed_multiset)::numeric, 10)
 ORDER BY recno;

-- Test union of incremental multiset.
--
SELECT curr.recno,
       curr.union_compressed_multiset,
       hll_union(curr.compressed_multiset, prev.union_compressed_multiset) 
  FROM test_bsnvqefe prev, test_bsnvqefe curr
 WHERE curr.recno > 1
   AND curr.recno = prev.recno + 1
   AND curr.union_compressed_multiset != 
       hll_union(curr.compressed_multiset, prev.union_compressed_multiset)
 ORDER BY curr.recno;

-- Test cardinality of union of incremental multiset.
--
SELECT curr.recno,
       curr.union_cardinality,
       hll_cardinality(hll_union(curr.compressed_multiset,
                                 prev.union_compressed_multiset))
  FROM test_bsnvqefe prev, test_bsnvqefe curr
 WHERE curr.recno > 1
   AND curr.recno = prev.recno + 1
   AND round(curr.union_cardinality::numeric, 10) != 
       round(hll_cardinality(hll_union(curr.compressed_multiset,
                                       prev.union_compressed_multiset))::numeric,
            10)
 ORDER BY curr.recno;

-- Test aggregate accumulation
--
SELECT v1.recno,
       v1.union_compressed_multiset,
       (select hll_union_agg(compressed_multiset)
          from test_bsnvqefe
         where recno <= v1.recno) as hll_union_agg
  FROM test_bsnvqefe v1
 WHERE v1.union_compressed_multiset !=
       (select hll_union_agg(compressed_multiset)
          from test_bsnvqefe
         where recno <= v1.recno)
 ORDER BY v1.recno;

-- Test aggregate accumulation with cardinality
--
SELECT v1.recno,
       ceil(v1.union_cardinality),
       (select ceiling(hll_cardinality(hll_union_agg(compressed_multiset)))
          from test_bsnvqefe
         where recno <= v1.recno) as ceiling
  FROM test_bsnvqefe v1
 WHERE ceil(v1.union_cardinality) !=
       (select ceiling(hll_cardinality(hll_union_agg(compressed_multiset)))
          from test_bsnvqefe
         where recno <= v1.recno)
 ORDER BY v1.recno;

DROP TABLE test_bsnvqefe;
