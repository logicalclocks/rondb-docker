# Create Config.ini


## Benchmarking

minikube start --driver=docker --cpus 10 --memory 20000

1 MySQLd, 1 data node, 1 bench (1 CPU), max 430%, sysbench_single

Final results for this test run
Threads: 1 Mean: 141
Threads: 2 Mean: 310
Threads: 4 Mean: 631
Threads: 8 Mean: 703
Threads: 12 Mean: 745
Threads: 16 Mean: 797
Threads: 24 Mean: 844
Threads: 32 Mean: 937

1 MySQLd, 1 data node, 1 bench (no CPU specified), max 430%, sysbench_single

Final results for this test run
Threads: 1 Mean: 137
Threads: 2 Mean: 320
Threads: 4 Mean: 608
Threads: 8 Mean: 677
Threads: 12 Mean: 734
Threads: 16 Mean: 747
Threads: 24 Mean: 816
Threads: 32 Mean: 861

1 MySQLd, 1 data node, 1 bench, max 430%, sysbench_single, USING explicit CPU requests

--> CPU maxes out at 8 threads...
Final results for this test run
Threads: 1 Mean: 140
Threads: 2 Mean: 321
Threads: 4 Mean: 618
Threads: 8 Mean: 684
Threads: 12 Mean: 762
Threads: 16 Mean: 824
Threads: 24 Mean: 886
Threads: 32 Mean: 914

2 MySQLds, 1 data node, 1 bench, max 730%, sysbench_multi, CPU requests < limits

Threads: 1 Mean: 311
Threads: 2 Mean: 587
Threads: 4 Mean: 1012
Threads: 8 Mean: 1430
Threads: 12 Mean: 1439
Threads: 16 Mean: 1512
Threads: 24 Mean: 1501
Threads: 32 Mean: 1484

2 MySQLds, 1 data node, 1 bench, max 800%, sysbench_multi, resource limits==requests

Threads: 1 Mean: 306
Threads: 2 Mean: 601
Threads: 4 Mean: 1007
Threads: 8 Mean: 1439
Threads: 12 Mean: 1632
Threads: 16 Mean: 1745
Threads: 24 Mean: 1897
Threads: 32 Mean: 1967
Threads: 64 Mean: 1972 <-- extra..

2 MySQLds, 1 data node, 1 bench, max 850%, sysbench_multi, OMITTING resource requests

Threads: 1 Mean: 320
Threads: 2 Mean: 614
Threads: 4 Mean: 1023
Threads: 8 Mean: 1492
Threads: 12 Mean: 1659
Threads: 16 Mean: 1767
Threads: 24 Mean: 1985
Threads: 32 Mean: 2065
